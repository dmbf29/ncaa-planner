class SeasonPreviewSerializer
  def initialize(season)
    @season = season
  end

  def as_json
    {
      focus: {
        season: @season.year,
        instructions: "This is a preseason preview covering our #{coached_college_seasons.size} coached teams for " \
                      "the #{@season.year} season. Use it to set storylines, expectations, and things to watch " \
                      "for heading into the year."
      },
      season: { id: @season.id, year: @season.year, dynasty: @season.dynasty.name },
      teams: coached_college_seasons.map { |cs| team_json(cs) },
      week_one_games: week_one_games_json,
      conference_landscape: conference_landscape_json,
      coached_matchups: coached_matchups_json
    }
  end

  private

  def coached_college_seasons
    @coached_college_seasons ||= @season.college_seasons
                                         .includes(:college, :coach, :student_seasons)
                                         .where.not(coach_id: nil)
                                         .joins(:college)
                                         .order("colleges.name")
  end

  def coached_college_ids
    @coached_college_ids ||= coached_college_seasons.map(&:college_id).to_set
  end

  def all_college_seasons
    @all_college_seasons ||= @season.college_seasons.includes(:college).to_a
  end

  def college_seasons_by_college_id
    @college_seasons_by_college_id ||= all_college_seasons.index_by(&:college_id)
  end

  def overall_ranked
    @overall_ranked ||= all_college_seasons.sort_by { |cs| -(cs.overall || -1) }
  end

  def team_json(college_season)
    {
      college: {
        id: college_season.college.id,
        name: college_season.college.name,
        conference: college_season.college.conference
      },
      coach: { id: college_season.coach.id, name: college_season.coach.name },
      ratings: {
        overall: college_season.overall,
        offense: college_season.offense,
        defense: college_season.defense,
        prestige: college_season.prestige
      },
      recruiting_rank: college_season.recruiting_rank,
      national_context: national_context_json(college_season),
      key_players: {
        offense: college_season.best_offensive_players.map { |ss| player_json(ss) },
        defense: college_season.best_defensive_players.map { |ss| player_json(ss) }
      },
      player_to_watch: player_to_watch_json(college_season),
      strengths: position_group_extremes(college_season, :top),
      weaknesses: position_group_extremes(college_season, :bottom),
      schedule_preview: schedule_preview_json(college_season)
    }
  end

  def national_context_json(college_season)
    ranked = conference_ranked(college_season.college.conference)

    {
      overall_rank: overall_ranked.index(college_season) + 1,
      total_colleges: overall_ranked.size,
      conference_rank: ranked.index(college_season) + 1,
      conference_size: ranked.size
    }
  end

  def conference_ranked(conference)
    @conference_ranked ||= {}
    @conference_ranked[conference] ||= all_college_seasons.select { |cs| cs.college.conference == conference }
                                                            .sort_by { |cs| -(cs.overall || -1) }
  end

  def player_to_watch_json(college_season)
    breakout = college_season.breakout_candidate
    chosen = breakout || college_season.most_valuable_player
    return nil unless chosen

    player_json(chosen).merge(reason: breakout ? "breakout_candidate" : "top_returning_talent")
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

  def position_group_extremes(college_season, edge)
    averages = college_season.position_group_averages.compact
    sorted = averages.sort_by { |_label, value| edge == :top ? -value : value }
    sorted.first(2).map { |label, value| { position_group: label, average: value } }
  end

  def schedule_preview_json(college_season)
    games_with_weeks = college_season.games
                                      .includes(:home_college, :away_college, :week)
                                      .map { |game| [ game, game.week ] }
                                      .sort_by { |_game, week| week.number }
    regular_season_games = games_with_weeks.reject { |_game, week| week.number.zero? }

    opener = regular_season_games.first
    toughest = regular_season_games.max_by { |game, _week| opponent_overall(game, college_season.college_id) || -1 }

    {
      opener: opener && game_preview_json(opener[0], opener[1], college_season.college_id),
      toughest_matchup: toughest && game_preview_json(toughest[0], toughest[1], college_season.college_id),
      bye_weeks: bye_week_numbers(games_with_weeks.map(&:first)),
      rivalry_games: regular_season_games.select { |game, _week| rivalry_game?(game, college_season.college_id) }
                                          .map { |game, week| game_preview_json(game, week, college_season.college_id) }
    }
  end

  def opponent_overall(game, college_id)
    opponent_id = game.home_college_id == college_id ? game.away_college_id : game.home_college_id
    college_seasons_by_college_id[opponent_id]&.overall
  end

  def rivalry_game?(game, college_id)
    opponent_id = game.home_college_id == college_id ? game.away_college_id : game.home_college_id
    coached_college_ids.include?(opponent_id)
  end

  def game_preview_json(game, week, college_id)
    home = game.home_college_id == college_id
    opponent_college = home ? game.away_college : game.home_college
    {
      week_number: week.number,
      opponent: { id: opponent_college.id, name: opponent_college.name },
      opponent_overall: college_seasons_by_college_id[opponent_college.id]&.overall,
      home: home
    }
  end

  def bye_week_numbers(scheduled_games)
    scheduled_week_ids = scheduled_games.map(&:week_id).to_set
    @season.weeks.where(post_season: false, conference_championship: false)
           .where.not(number: 0)
           .reject { |week| scheduled_week_ids.include?(week.id) }
           .map(&:number)
  end

  def coached_matchups_json
    games = Game.where(week_id: @season.week_ids, home_college_id: coached_college_ids, away_college_id: coached_college_ids)
                .includes(:home_college, :away_college, :week)

    games.map do |game|
      {
        week_number: game.week.number,
        home: { id: game.home_college.id, name: game.home_college.name },
        away: { id: game.away_college.id, name: game.away_college.name }
      }
    end.sort_by { |matchup| matchup[:week_number] }
  end

  def week_one_games_json
    week_one = @season.weeks.find_by(number: 1)
    return [] unless week_one

    coached_college_seasons.map do |college_season|
      game = college_season.games.includes(:home_college, :away_college).find { |g| g.week_id == week_one.id }
      {
        college: { id: college_season.college.id, name: college_season.college.name },
        coach: { id: college_season.coach.id, name: college_season.coach.name },
        opponent: game && week_one_opponent_json(game, college_season.college_id)
      }
    end
  end

  def week_one_opponent_json(game, college_id)
    home = game.home_college_id == college_id
    opponent_college = home ? game.away_college : game.home_college
    {
      id: opponent_college.id,
      name: opponent_college.name,
      home: home,
      overall: college_seasons_by_college_id[opponent_college.id]&.overall
    }
  end

  def conference_landscape_json
    conferences = coached_college_seasons.map { |cs| cs.college.conference }.uniq.compact

    conferences.map do |conference|
      ranked = conference_ranked(conference)
      others = ranked.reject { |cs| coached_college_ids.include?(cs.college_id) }

      { conference: conference, teams: others.map { |cs| conference_rival_json(cs, ranked) } }
    end
  end

  def conference_rival_json(college_season, ranked_within_conference)
    {
      college: { id: college_season.college.id, name: college_season.college.name },
      overall: college_season.overall,
      offense: college_season.offense,
      defense: college_season.defense,
      conference_rank: ranked_within_conference.index(college_season) + 1,
      national_rank: overall_ranked.index(college_season) + 1
    }
  end
end
