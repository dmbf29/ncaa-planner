class SeasonDashboardSerializer
  def initialize(season)
    @season = season
  end

  def as_json
    teams = coached_college_seasons.map { |cs| team_json(cs) }

    {
      id: @season.id,
      year: @season.year,
      dynasty: { id: @season.dynasty.id, name: @season.dynasty.name },
      teams: teams,
      current_week_number: current_week_number(teams),
      top_25: top_25_json,
      heisman_watch: heisman_watch_json,
      around_the_league: around_the_league_json
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

  # The most recent week (by number) that actually has rankings/candidates
  # entered — lets the dashboard show "current" league context regardless
  # of how far into the season the data entry has gotten.
  def latest_ranked_week
    return @latest_ranked_week if defined?(@latest_ranked_week)

    @latest_ranked_week = @season.weeks
                                  .joins(:college_week_rankings)
                                  .order(number: :desc)
                                  .first
  end

  # The last 3 weeks (most recent first) that actually have Heisman
  # candidates entered, so the dashboard can show the watch's recent trend
  # rather than just a single snapshot week.
  def recent_heisman_weeks
    return @recent_heisman_weeks if defined?(@recent_heisman_weeks)

    @recent_heisman_weeks = @season.weeks
                                    .joins(:heisman_candidates)
                                    .distinct
                                    .order(number: :desc)
                                    .limit(3)
                                    .includes(heisman_candidates: [ student_season: [ :student, { college_season: :college } ] ])
  end

  def top_25_json
    return { week: nil, rankings: [] } unless latest_ranked_week

    rankings = latest_ranked_week.college_week_rankings
                                  .includes(:college)
                                  .order(:ranking)
                                  .map { |cwr| top_25_ranking_json(cwr) }

    { week: { id: latest_ranked_week.id, number: latest_ranked_week.number, name: latest_ranked_week.name },
      rankings: rankings }
  end

  def college_seasons_by_college_id
    @college_seasons_by_college_id ||= @season.college_seasons.index_by(&:college_id)
  end

  def top_25_ranking_json(cwr)
    college_season = college_seasons_by_college_id[cwr.college_id]

    {
      rank: cwr.ranking,
      college: { id: cwr.college.id, name: cwr.college.name, conference: cwr.college.conference },
      coached_by_us: coached_college_ids.include?(cwr.college_id),
      record: college_season && { wins: college_season.wins, losses: college_season.losses },
      last_result: college_season && top_25_last_result_json(college_season)
    }
  end

  # The most recent played game through the latest ranked week — "how'd
  # they do last time out."
  def top_25_last_result_json(college_season)
    game = college_season.games
                          .includes(:home_college, :away_college, :college_game_stats, :week)
                          .select { |g| g.week.number <= latest_ranked_week.number && g.played? }
                          .max_by { |g| g.week.number }
    return nil unless game

    stats = game.college_game_stats.index_by(&:college_id)
    team_stat = stats[college_season.college_id]
    opponent_college = game.home_college_id == college_season.college_id ? game.away_college : game.home_college
    opponent_stat = stats[opponent_college.id]
    return nil unless team_stat&.final_score && opponent_stat&.final_score

    {
      opponent: { id: opponent_college.id, name: opponent_college.name },
      team_score: team_stat.final_score,
      opponent_score: opponent_stat.final_score,
      won: team_stat.final_score > opponent_stat.final_score
    }
  end

  def heisman_watch_json
    winner = @season.heisman && player_json(@season.heisman).merge(
      college: { id: @season.heisman.college_season.college.id, name: @season.heisman.college_season.college.name }
    )

    {
      winner: winner,
      weeks: recent_heisman_weeks.map do |week|
        {
          week: { id: week.id, number: week.number, name: week.name },
          candidates: week.heisman_candidates.map { |hc| heisman_candidate_json(hc) }
        }
      end
    }
  end

  # The earliest week any coached team still has left to play — what a
  # coach means by "this week" when they open the dashboard.
  def current_week_number(teams)
    teams.filter_map { |t| t[:next_game]&.dig(:week, :number) }.min
  end

  # Every game NOT involving a coached team, grouped by week — i.e.
  # everything a coach can't already see on one of their own team cards —
  # so the dashboard can show what's happening around the rest of the league.
  def around_the_league_json
    @season.weeks
           .order(:number)
           .includes(games: %i[home_college away_college college_game_stats])
           .filter_map do |week|
      games = week.games.reject do |g|
        coached_college_ids.include?(g.home_college_id) || coached_college_ids.include?(g.away_college_id)
      end
      next if games.empty?

      { week: { id: week.id, number: week.number, name: week.name }, games: games.map { |g| league_game_json(g) } }
    end
  end

  def league_game_json(game)
    stats = game.college_game_stats.index_by(&:college_id)
    home_stat = stats[game.home_college_id]
    away_stat = stats[game.away_college_id]
    played = home_stat&.final_score && away_stat&.final_score

    {
      id: game.id,
      time: game.time,
      home: { id: game.home_college.id, name: game.home_college.name },
      away: { id: game.away_college.id, name: game.away_college.name },
      result: played ? { home_score: home_stat.final_score, away_score: away_stat.final_score } : nil
    }
  end

  def heisman_candidate_json(candidate)
    student_season = candidate.student_season
    player_json(student_season).merge(
      college: {
        id: student_season.college_season.college.id,
        name: student_season.college_season.college.name
      }
    )
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
      nil_spend: college_season.nil_spend,
      current_rank: current_rank(college_season),
      next_game: next_game_json(college_season),
      best_offensive_players: college_season.best_offensive_players.map { |ss| player_json(ss) },
      best_defensive_players: college_season.best_defensive_players.map { |ss| player_json(ss) },
      position_group_averages: college_season.position_group_averages,
      weeks: weeks_json(college_season)
    }
  end

  def current_rank(college_season)
    return nil unless latest_ranked_week

    latest_ranked_week.college_week_rankings.find { |cwr| cwr.college_id == college_season.college_id }&.ranking
  end

  # The next week (in order) where this team has a scheduled game that
  # hasn't been played yet — what a coach checks the dashboard for mid-week.
  # Uses Game#played? (rather than duplicating its "2 stat rows" logic in
  # SQL) since the number of games per team per season is small.
  def next_game_json(college_season)
    upcoming = college_season.games
                              .includes(:home_college, :away_college, :college_game_stats, :week)
                              .sort_by { |g| g.week.number }
                              .find { |g| !g.played? }
    return nil unless upcoming

    {
      week: { id: upcoming.week.id, number: upcoming.week.number, name: upcoming.week.name },
      opponent: opponent_json(upcoming, college_season.college_id)
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
        game_id: game&.id,
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
