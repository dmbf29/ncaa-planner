class SeasonDashboardSerializer
  # category => primary StudentGameStat column that decides that category's leader
  STAT_LEADER_CATEGORIES = {
    passing: :passing_yards,
    rushing: :rushing_yards,
    receiving: :receiving_yards,
    sacks: :defense_sacks
  }.freeze

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
      top_25: top_25_json,
      heisman_watch: heisman_watch_json,
      around_the_league: around_the_league_json,
      last_played_week_number: last_played_week_number
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
    winner = @season.heisman && player_json(@season.heisman).merge(college: heisman_college_json(@season.heisman))

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

  # The most recent week (season-wide, any game) that's actually been
  # played — lets the dashboard show a "review" of last week's results
  # alongside a "preview" of the week after, regardless of whether our own
  # coached teams happen to have a bye that week.
  def last_played_week_number
    return @last_played_week_number if defined?(@last_played_week_number)

    @last_played_week_number = @season.weeks
                                       .includes(games: :college_game_stats)
                                       .select { |week| week.games.any?(&:played?) }
                                       .map(&:number)
                                       .max
  end

  # Every game NOT involving a coached team, grouped by week — i.e.
  # everything a coach can't already see on one of their own team cards —
  # so the dashboard can show what's happening around the rest of the league.
  # Every week is included (even ones with no non-coached games) so the
  # frontend can always find the specific review/preview week it wants.
  def around_the_league_json
    @season.weeks
           .order(:number)
           .includes(games: %i[home_college away_college college_game_stats])
           .map do |week|
      games = week.games.reject do |g|
        coached_college_ids.include?(g.home_college_id) || coached_college_ids.include?(g.away_college_id)
      end

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
      home: { id: game.home_college.id, name: game.home_college.name, rank: rank_for_college(game.home_college_id) },
      away: { id: game.away_college.id, name: game.away_college.name, rank: rank_for_college(game.away_college_id) },
      result: played ? { home_score: home_stat.final_score, away_score: away_stat.final_score } : nil
    }
  end

  def heisman_candidate_json(candidate)
    student_season = candidate.student_season
    player_json(student_season).merge(college: heisman_college_json(student_season))
  end

  def heisman_college_json(student_season)
    college = student_season.college_season.college
    { id: college.id, name: college.name, rank: rank_for_college(college.id) }
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
      stat_leaders: team_stat_leaders_json(college_season),
      position_group_averages: college_season.position_group_averages,
      weeks: weeks_json(college_season)
    }
  end

  # Passing/rushing/receiving/sack leaders for this team specifically, once
  # it has any recorded game stats — nil until then, so the frontend can
  # keep showing the rating-based best_offensive/defensive_players instead.
  def team_stat_leaders_json(college_season)
    game_stats = StudentGameStat.joins(:student_season)
                                 .where(student_seasons: { college_season_id: college_season.id })
                                 .includes(student_season: :student)
                                 .to_a
    return nil if game_stats.empty?

    totals_by_student_season = game_stats.group_by(&:student_season).transform_values do |rows|
      STAT_LEADER_CATEGORIES.values.index_with { |column| rows.sum { |r| r.public_send(column) || 0 } }
    end

    STAT_LEADER_CATEGORIES.transform_values { |column| team_category_leader_json(totals_by_student_season, column) }
  end

  def team_category_leader_json(totals_by_student_season, column)
    student_season, totals = totals_by_student_season.select { |_ss, totals| totals[column].positive? }
                                                       .max_by { |_ss, totals| totals[column] }
    return nil unless student_season

    player_json(student_season).merge(value: totals[column])
  end

  def current_rank(college_season)
    rank_for_college(college_season.college_id)
  end

  # This week's Top 25 rank for any college (not just coached ones) — used
  # everywhere a team name shows up (schedules, Around the League, Heisman
  # Watch) so a ranked opponent reads as ranked wherever it appears.
  def rank_for_college(college_id)
    return nil unless latest_ranked_week

    latest_ranked_week.college_week_rankings.find { |cwr| cwr.college_id == college_id }&.ranking
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
      user_coached: coached_college_ids.include?(opponent_college.id),
      rank: rank_for_college(opponent_college.id)
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
