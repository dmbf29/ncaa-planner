module ConferenceStandings
  # Persists a (possibly user-edited) conference standings table for one
  # season. Purely team-level data — no Student/StudentSeason involved — so
  # each row just finds-or-creates the CollegeSeason (same reasoning as
  # NilSpend/ScheduleStats: a freshly-started season won't have one yet for
  # anything but the coached teams) and overwrites its standings columns
  # with this upload, since it's meant to be the definitive current status,
  # not a merge.
  #
  # Each row commits independently and a validation failure is caught and
  # reported as a warning rather than aborting the rest of the batch,
  # mirroring the other CommitServices.
  class CommitService
    def initialize(season)
      @season = season
    end

    def call(rows)
      Array(rows).filter_map do |row|
        symbolized = row.deep_symbolize_keys
        commit_row(symbolized)
        nil
      rescue ActiveRecord::RecordInvalid => e
        { team: symbolized[:college_raw_name], error: e.message }
      end
    end

    private

    def commit_row(row)
      college = College.find_by(id: row[:college_id])
      return if college.blank?

      college_season = CollegeSeason.find_or_create_by!(college: college, season: @season)
      college_season.update!(
        conference_wins: row[:conference_wins],
        conference_losses: row[:conference_losses],
        conference_points_for: row[:conference_points_for],
        conference_points_against: row[:conference_points_against],
        wins: row[:wins],
        losses: row[:losses],
        points_for: row[:points_for],
        points_against: row[:points_against],
        home_wins: row[:home_wins],
        home_losses: row[:home_losses]
      )
    end
  end
end
