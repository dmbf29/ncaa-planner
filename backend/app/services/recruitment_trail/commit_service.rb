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
  #   - class_year only overwrites when the new row actually has one (the
  #     column isn't always visible/extracted); transfer overwrites
  #     whenever the row explicitly states it (including false), since
  #     Extractor always sends one now.
  #
  # Transfers are also linked to their previous-roster Student (see
  # TransferMatcher), chosen on the review screen via the row's student_id —
  # that link is how their overall is found later.
  #
  # Each row commits independently; a validation failure is reported as a
  # warning rather than aborting the batch, mirroring the other
  # CommitServices.
  class CommitService
    ATHLETE = "ATH".freeze

    def initialize(college_season, week)
      @college_season = college_season
      @week = week
      @transfer_matcher = RecruitmentTrail::TransferMatcher.new(college_season.season)
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

      recruit = find_or_build_recruit(row)
      recruit.week = @week if recruit.new_record?
      recruit.position = row[:position] unless row[:position] == ATHLETE # never back to "ATH" once placed
      recruit.first_name = row[:first_name] if row[:first_name].present? || recruit.first_name.blank?
      recruit.star_rating = row[:star_rating]
      recruit.nil_amount = row[:nil_amount]
      recruit.national_rank = row[:national_rank]
      recruit.position_rank = row[:position_rank]
      recruit.state_rank = row[:state_rank]
      recruit.class_year = row[:class_year] if row[:class_year].present?
      recruit.transfer = row[:transfer] unless row[:transfer].nil?
      assign_student(recruit, row) if recruit.transfer
      recruit.save!
    end

    # A recruit marked signed from the recruit pool has the pool's position, usually "ATH" (undecided); the
    # signing screen later shows the position the coach placed them at. Same last name, state and national
    # rank is the same person, so that updates the row instead of adding a second one.
    def find_or_build_recruit(row)
      signed = @college_season.signed_recruits
      state = row[:state].presence
      signed.find_by(last_name: row[:last_name], position: row[:position], state: state) ||
        (signed.find_by(last_name: row[:last_name], state: state, national_rank: row[:national_rank]) if row[:national_rank].present?) ||
        signed.new(last_name: row[:last_name], position: row[:position], state: state)
    end

    # The reviewer's choice wins whenever the row carries one (including an
    # explicit nil = "not linked"); only rows without the key (older
    # clients) fall back to an automatic match.
    def assign_student(recruit, row)
      if row.key?(:student_id)
        recruit.student_id = row[:student_id]
        recruit.first_name = recruit.student.first_name if recruit.first_name.blank? && recruit.student
      elsif recruit.student_id.nil?
        recruit.student = @transfer_matcher.student_for(recruit)
      end
    end

    def recruit_label(row)
      [ row[:first_name].presence || row[:first_initial], row[:last_name] ].compact.join(" ").strip.presence || "recruit"
    end
  end
end
