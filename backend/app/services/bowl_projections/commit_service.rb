module BowlProjections
  # Persists a (possibly user-edited) bowl projections extraction for one
  # observation week. Upserts each row by its full projected matchup —
  # bowl name PLUS both projected colleges — rather than bowl name alone:
  # names like "CFP First Round" are reused across several distinct games
  # in the same week (the bracket isn't seeded into individually-named
  # bowls yet), so a name-only key can't tell them apart, but keying on
  # the whole matchup still collapses an exact duplicate (e.g. the same
  # game read twice off two overlapping screenshots) down to one row.
  #
  # Deliberately does NOT clear the week's other projections first —
  # uploading a follow-up screenshot to fill in games missed the first
  # time should only add/update those rows, never wipe out an earlier
  # save. Use the review list's Delete button for anything that needs to
  # come out entirely. Each row still commits independently — one bad row
  # doesn't block the rest — mirroring RankingStats::CommitService.
  class CommitService
    def initialize(week)
      @week = week
      @season_year = week.season.year
    end

    def call(rows)
      Array(rows).filter_map do |row|
        symbolized = row.deep_symbolize_keys
        commit_row(symbolized)
        nil
      rescue ActiveRecord::RecordInvalid => e
        { bowl_name: symbolized[:bowl_name], error: e.message }
      end
    end

    private

    def commit_row(row)
      return if row[:bowl_name].blank?

      projection = @week.bowl_projections.find_or_initialize_by(
        bowl_name: row[:bowl_name],
        projected_away_college_id: row[:away_college_id],
        projected_home_college_id: row[:home_college_id]
      )
      attributes = { cfp_round: row[:cfp_round] }
      # Never null out an already-recorded time just because this commit's
      # row happened to be missing date info — same caution as
      # ScheduleStats::CommitService#update_time — only a freshly-parsed
      # value replaces it.
      time = parse_time(row[:month], row[:day], row[:time_of_day])
      attributes[:time] = time if time
      projection.update!(attributes)
    end

    # A bowl's calendar date can fall in January of the year after the
    # season started, regardless of which regular-season week this
    # projection was observed on — unlike ScheduleStats::CommitService,
    # whose Game rows live in an actual post-season week, a
    # BowlProjection's `week` is just when the screenshot was captured, so
    # the month alone (not the observation week) decides the year here.
    def parse_time(month, day, time_of_day)
      return nil if month.blank? || day.blank? || time_of_day.blank?

      match = time_of_day.match(/(\d{1,2}):(\d{2})\s*(AM|PM)/i)
      return nil unless match

      hour = match[1].to_i % 12
      hour += 12 if match[3].casecmp?("PM")
      year = month.to_i == 1 ? @season_year + 1 : @season_year
      Time.new(year, month, day, hour, match[2].to_i)
    rescue ArgumentError
      nil
    end
  end
end
