module CoachContinuity
  # Applies chosen coach -> college assignments to a newly created season.
  # Each row clears the coach off any other CollegeSeason in this season
  # first (so resubmitting, or changing a prior choice, can't leave a coach
  # double-booked), then assigns them to the target college if one was
  # chosen. Two rows claiming the same college within a single call are
  # resolved first-write-wins, with the later row reported as a warning
  # rather than silently overwriting the earlier one.
  class CommitService
    def initialize(season)
      @season = season
      @claimed_college_ids = []
    end

    def call(assignments)
      Array(assignments).filter_map { |row| commit_row(row.deep_symbolize_keys) }
    end

    private

    def commit_row(row)
      coach = Coach.find_by(id: row[:coach_id])
      return { coach: nil, error: "Coach not found" } unless coach && coach.dynasty_id == @season.dynasty_id

      college_id = row[:college_id]
      if college_id.present? && @claimed_college_ids.include?(college_id)
        return { coach: coach.name, error: "Another coach already claimed this college in this save; #{coach.name} was left unassigned." }
      end

      assign_coach(coach, college_id)
      @claimed_college_ids << college_id if college_id.present?
      nil
    rescue ActiveRecord::RecordInvalid => e
      { coach: coach&.name, error: e.message }
    end

    def assign_coach(coach, college_id)
      @season.college_seasons.where(coach_id: coach.id).where.not(college_id: college_id).find_each do |college_season|
        college_season.update!(coach_id: nil)
      end
      return if college_id.blank?

      college_season = @season.college_seasons.find_by(college_id: college_id)
      college_season&.update!(coach_id: coach.id)
    end
  end
end
