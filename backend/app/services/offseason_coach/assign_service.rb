module OffseasonCoach
  # Points one coach at a new program for the offseason: clears any earlier
  # move for that coach in this season, then (unless college_id is blank)
  # records them on the target's CollegeSeason#offseason_coach. Refuses a
  # target that another coach still holds for the offseason, so two coaches
  # can't end up on one program.
  class AssignService
    def initialize(season)
      @season = season
    end

    def call(coach_id:, college_id:)
      coach = @season.dynasty.coaches.find_by(id: coach_id)
      return { error: "Coach not found" } unless coach

      target = college_id.present? ? @season.college_seasons.includes(:college).find_by(college_id: college_id) : nil
      return { error: "College not found" } if college_id.present? && target.nil?

      holder = target&.offseason_coach_record
      return { error: "#{target.college.name} already has a coach for the offseason." } if holder && holder.id != coach.id

      CollegeSeason.transaction do
        @season.college_seasons.where(offseason_coach_id: coach.id).update_all(offseason_coach_id: nil)
        target&.update!(offseason_coach_id: coach.id)
      end
      { coach_id: coach.id, college_id: target&.college_id }
    end
  end
end
