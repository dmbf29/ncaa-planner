# Every college with a CollegeSeason row for a season in one flat list, with the
# game's hand-entered ratings next to the saved starter-based ones
# (StarterRatings), so the two can be compared and sorted.
class TeamRatingsSerializer
  def initialize(season)
    @season = season
  end

  def as_json
    {
      season: { id: @season.id, year: @season.year },
      calculated_at: calculated_at,
      teams: @season.college_seasons.includes(:college).map { |cs| team_json(cs) }
    }
  end

  private

  # The Top 25 rank from the most recent week with rankings entered, the same
  # "current" week the dashboard uses; empty before any rankings exist.
  def current_ranks
    @current_ranks ||= begin
      week = @season.weeks.joins(:college_week_rankings).order(number: :desc).first
      week ? week.college_week_rankings.to_h { |ranking| [ ranking.college_id, ranking.ranking ] } : {}
    end
  end

  def calculated_at
    @season.college_seasons.where.not(starter_overall: nil).maximum(:updated_at)
  end

  def team_json(college_season)
    {
      id: college_season.id,
      college: { id: college_season.college.id, name: college_season.college.name },
      rank: current_ranks[college_season.college_id],
      conference: college_season.conference,
      prestige: college_season.prestige,
      overall: college_season.overall,
      offense: college_season.offense,
      defense: college_season.defense,
      starter_overall: college_season.starter_overall,
      starter_offense: college_season.starter_offense,
      starter_defense: college_season.starter_defense
    }
  end
end
