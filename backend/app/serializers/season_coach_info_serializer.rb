# The user-coached teams for a season with the coach-level numbers (NIL amount,
# job security) that the game doesn't expose any other way, so they're entered by hand.
class SeasonCoachInfoSerializer
  def initialize(season)
    @season = season
  end

  def as_json
    {
      season: { id: @season.id, year: @season.year },
      coaches: coached_college_seasons.map { |cs| coach_json(cs) }
    }
  end

  private

  def coached_college_seasons
    @season.college_seasons.includes(:college, :coach).where.not(coach_id: nil).sort_by { |cs| cs.coach.name }
  end

  def coach_json(college_season)
    coach = college_season.coach
    {
      coach: {
        id: coach.id,
        name: coach.name,
        nil_amount: coach.nil_amount,
        job_security: coach.job_security,
        job_security_label: coach.job_security_label
      },
      college: { id: college_season.college.id, name: college_season.college.name }
    }
  end
end
