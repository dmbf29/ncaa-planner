# Every game in one week, coached or not — the "click through to every
# result" counterpart to SeasonDashboardSerializer#around_the_league, which
# only shows the non-coached teaser on the main dashboard.
class WeekGamesSerializer
  def initialize(week)
    @week = week
  end

  def as_json
    {
      week: { id: @week.id, number: @week.number, name: @week.name },
      games: @week.games.includes(:home_college, :away_college, :college_game_stats).map { |g| game_json(g) }
    }
  end

  private

  def coached_college_ids
    @coached_college_ids ||= @week.season.college_seasons.where.not(coach_id: nil).pluck(:college_id).to_set
  end

  def game_json(game)
    stats = game.college_game_stats.index_by(&:college_id)
    home_stat = stats[game.home_college_id]
    away_stat = stats[game.away_college_id]
    played = home_stat&.final_score && away_stat&.final_score

    {
      id: game.id,
      time: game.time,
      bowl_name: game.bowl_name,
      cfp_round: game.cfp_round,
      home: side_json(game.home_college),
      away: side_json(game.away_college),
      result: played ? { home_score: home_stat.final_score, away_score: away_stat.final_score } : nil
    }
  end

  def side_json(college)
    { id: college.id, name: college.name, coached_by_us: coached_college_ids.include?(college.id) }
  end
end
