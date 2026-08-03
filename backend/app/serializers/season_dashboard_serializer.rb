class SeasonDashboardSerializer
  def initialize(season)
    @season = season
  end

  def as_json
    {
      id: @season.id,
      year: @season.year,
      dynasty: { id: @season.dynasty.id, name: @season.dynasty.name },
      teams: coached_college_seasons.map { |cs| team_json(cs) }
    }
  end

  private

  def coached_college_seasons
    @season.college_seasons
           .includes(:college, :coach, :student_seasons)
           .where.not(coach_id: nil)
           .joins(:college)
           .order("colleges.name")
  end

  def coached_college_ids
    @coached_college_ids ||= @season.college_seasons.where.not(coach_id: nil).pluck(:college_id).to_set
  end

  def team_json(college_season)
    {
      id: college_season.id,
      college: {
        id: college_season.college.id,
        name: college_season.college.name,
        conference: college_season.college.conference
      },
      coach: { id: college_season.coach.id, name: college_season.coach.name },
      overall: college_season.overall,
      offense: college_season.offense,
      defense: college_season.defense,
      prestige: college_season.prestige,
      recruiting_rank: college_season.recruiting_rank,
      wins: college_season.wins,
      losses: college_season.losses,
      best_offensive_players: college_season.best_offensive_players.map { |ss| player_json(ss) },
      best_defensive_players: college_season.best_defensive_players.map { |ss| player_json(ss) },
      position_group_averages: college_season.position_group_averages,
      weeks: weeks_json(college_season)
    }
  end

  def player_json(student_season)
    return nil unless student_season

    {
      id: student_season.id,
      name: student_season.student.name,
      position: student_season.position,
      overall: student_season.overall,
      dev_trait: student_season.dev_trait,
      class_year: student_season.class_year
    }
  end

  def weeks_json(college_season)
    games_by_week = college_season.games.includes(:home_college, :away_college, :college_game_stats).index_by(&:week_id)

    @season.weeks.order(:number).map do |week|
      game = games_by_week[week.id]
      {
        id: week.id,
        number: week.number,
        name: week.name,
        conference_championship: week.conference_championship,
        post_season: week.post_season,
        opponent: opponent_json(game, college_season.college_id),
        result: result_json(game, college_season.college_id)
      }
    end
  end

  def opponent_json(game, college_id)
    return nil unless game

    home = game.home_college_id == college_id
    opponent_college = home ? game.away_college : game.home_college
    {
      id: opponent_college.id,
      name: opponent_college.name,
      home: home,
      user_coached: coached_college_ids.include?(opponent_college.id)
    }
  end

  def result_json(game, college_id)
    return nil unless game

    stats = game.college_game_stats.index_by(&:college_id)
    team_stat = stats[college_id]
    opponent_stat = stats.values.find { |s| s.college_id != college_id }
    return nil unless team_stat&.final_score && opponent_stat&.final_score

    {
      team_score: team_stat.final_score,
      opponent_score: opponent_stat.final_score,
      won: team_stat.final_score > opponent_stat.final_score
    }
  end
end
