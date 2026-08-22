class SeasonCoachAssignmentsSerializer
  def initialize(season)
    @season = season
  end

  def as_json
    {
      assignments: assignments_json,
      colleges: colleges_json
    }
  end

  private

  def assignments_json
    previous_coached_college_seasons.map do |previous_college_season|
      coach = previous_college_season.coach
      current_college_season = current_college_seasons_by_coach_id[coach.id]

      {
        coach_id: coach.id,
        coach_name: coach.name,
        previous_college_id: previous_college_season.college_id,
        previous_college_name: previous_college_season.college.name,
        current_college_id: current_college_season&.college_id,
        current_college_name: current_college_season&.college&.name
      }
    end
  end

  def previous_coached_college_seasons
    return CollegeSeason.none unless @season.previous_season

    @season.previous_season.college_seasons.includes(:coach, :college).where.not(coach_id: nil).joins(:college).order("colleges.name")
  end

  def current_college_seasons_by_coach_id
    @current_college_seasons_by_coach_id ||= @season.college_seasons
                                                      .includes(:college)
                                                      .where.not(coach_id: nil)
                                                      .index_by(&:coach_id)
  end

  def colleges_json
    College.order(:name).map { |college| { id: college.id, name: college.name } }
  end
end
