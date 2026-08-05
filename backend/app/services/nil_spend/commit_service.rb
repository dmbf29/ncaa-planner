module NilSpend
  # Persists a (possibly user-edited) conference NIL spend table for one
  # season. Purely team-level data — no Student/StudentSeason involved —
  # so each row just finds-or-creates the CollegeSeason (same reasoning as
  # ScheduleStats/AllAmericans: a freshly-started season won't have one yet
  # for anything but the coached teams) and overwrites its nil_spend /
  # nil_spend_by_position with this upload, since a once-a-season upload is
  # meant to be the definitive replacement, not a merge.
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
        nil_spend: row[:nil_total],
        nil_spend_by_position: by_position_hash(row[:by_position])
      )
    end

    # Wire format is an array of {position:, amount:} rather than a
    # {"QB" => amount} hash — see Extractor#build_row for why — so it's
    # converted back to a hash here for JSONB storage.
    def by_position_hash(entries)
      Array(entries).each_with_object({}) do |entry, hash|
        next if entry[:position].blank?

        hash[entry[:position]] = entry[:amount]
      end
    end
  end
end
