module RecruitmentTrail
  # Persists a (user-reviewed) list of signed recruits for one coached
  # program in one season. The college_season and week are resolved by the
  # controller from the team/week the user picked before uploading.
  #
  # Rows upsert by [college_season, last_name, position, state] so
  # re-uploading a corrected or fuller screenshot updates the existing
  # recruit instead of duplicating them. On an update:
  #   - week_id is left untouched — it records when the signing was FIRST
  #     seen, which is what the weekly podcast keys "newly signed this
  #     week" off of.
  #   - a first_name already filled in by hand is never overwritten with a
  #     blank from a fresh extract.
  #
  # Each row commits independently; a validation failure is reported as a
  # warning rather than aborting the batch, mirroring the other
  # CommitServices.
  class CommitService
    def initialize(college_season, week)
      @college_season = college_season
      @week = week
    end

    def call(rows)
      Array(rows).filter_map do |raw_row|
        row = raw_row.deep_symbolize_keys
        commit_row(row)
        nil
      rescue ActiveRecord::RecordInvalid => e
        { recruit: recruit_label(row), error: e.message }
      end
    end

    private

    def commit_row(row)
      return if row[:last_name].blank? || row[:position].blank?

      recruit = @college_season.signed_recruits.find_or_initialize_by(
        last_name: row[:last_name], position: row[:position], state: row[:state].presence
      )
      recruit.week = @week if recruit.new_record?
      recruit.first_name = row[:first_name] if row[:first_name].present? || recruit.first_name.blank?
      recruit.star_rating = row[:star_rating]
      recruit.nil_amount = row[:nil_amount]
      recruit.national_rank = row[:national_rank]
      recruit.position_rank = row[:position_rank]
      recruit.state_rank = row[:state_rank]
      recruit.save!
    end

    def recruit_label(row)
      [ row[:first_name].presence || row[:first_initial], row[:last_name] ].compact.join(" ").strip.presence || "recruit"
    end
  end
end
