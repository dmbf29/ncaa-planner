# Preseason "Vegas win total" episode: a projected win total (see
# WinTotals::Calculator) for each of our coached teams, plus everything the
# two hosts need to debate it — full schedule, home/away splits, opponent
# ratings and key players game-by-game, and past head-to-head results once
# the dynasty has more than one season on the books.
class WinTotalsSerializer
  def initialize(season)
    @season = season
    @calculator = WinTotals::Calculator.new
  end

  def as_json
    {
      focus: focus_json,
      season: { id: @season.id, year: @season.year, dynasty: @season.dynasty.name },
      teams: coached_college_seasons.map { |cs| team_json(cs) },
      conference_landscape: conference_landscape_json,
      champion_predictions: champion_predictions_json
    }
  end

  private

  def focus_json
    {
      instructions: "This is a Vegas-style win-totals debate for our #{coached_college_seasons.size} coached " \
                    "teams heading into the #{@season.year} season — no games have been played yet. Each team " \
                    "has a projected win total ending in .5. One host argues the OVER, the other argues the " \
                    "UNDER, using strength of schedule, home/away splits, and the opponent-by-opponent detail " \
                    "below as ammunition."
    }
  end

  def coached_college_seasons
    @coached_college_seasons ||= @season.college_seasons
                                         .includes(:college, :coach, student_seasons: :student)
                                         .where.not(coach_id: nil)
                                         .joins(:college)
                                         .order("colleges.name")
                                         .to_a
  end

  def coached_college_ids
    @coached_college_ids ||= coached_college_seasons.map(&:college_id).to_set
  end

  def all_college_seasons
    @all_college_seasons ||= @season.college_seasons.includes(:college, student_seasons: :student).to_a
  end

  def college_seasons_by_college_id
    @college_seasons_by_college_id ||= all_college_seasons.index_by(&:college_id)
  end

  # Empty until the dynasty has a prior season, but built to "just work"
  # from next season onward without any further changes.
  def previous_season_college_seasons_by_college_id
    @previous_season_college_seasons_by_college_id ||= @season.previous_season&.college_seasons&.index_by(&:college_id) || {}
  end

  def previous_season_record_json(college_id)
    college_season = previous_season_college_seasons_by_college_id[college_id]
    return nil unless college_season
    return nil if college_season.wins.nil? && college_season.losses.nil?

    {
      wins: college_season.wins,
      losses: college_season.losses,
      conference_wins: college_season.conference_wins,
      conference_losses: college_season.conference_losses
    }
  end

  def strength_ranked
    @strength_ranked ||= all_college_seasons.filter_map { |cs| [ cs, @calculator.team_strength(cs) ] }
                                             .select { |_cs, strength| strength }
                                             .sort_by { |_cs, strength| -strength }
  end

  def team_json(college_season)
    games = scheduled_games(college_season)
    schedule = games.map { |g| game_json(g) }

    {
      college: college_json(college_season.college),
      coach: { id: college_season.coach.id, name: college_season.coach.name },
      ratings: ratings_json(college_season),
      previous_season_record: previous_season_record_json(college_season.college_id),
      vegas_win_total: @calculator.vegas_win_total(college_season, games),
      schedule_summary: schedule_summary_json(schedule),
      key_players: key_players_json(college_season),
      position_group_averages: college_season.position_group_averages.compact,
      schedule: schedule
    }
  end

  def schedule_summary_json(schedule)
    {
      likely_wins: schedule.count { |g| g[:projection] == :likely_win },
      likely_losses: schedule.count { |g| g[:projection] == :likely_loss },
      coin_flips: schedule.count { |g| g[:projection] == :coin_flip }
    }
  end

  def college_json(college)
    { id: college.id, name: college.name, conference: college.conference }
  end

  def ratings_json(college_season)
    return nil unless college_season

    { overall: college_season.overall, offense: college_season.offense, defense: college_season.defense }
  end

  # Every regular-season game (week 0 is preseason/exhibition, so it's
  # excluded same as the other broadcast serializers).
  def scheduled_games(college_season)
    college_season.games
                   .includes(:home_college, :away_college, week: :season)
                   .map { |game| [ game, game.week ] }
                   .reject { |_game, week| week.number.zero? }
                   .sort_by { |_game, week| week.number }
                   .map { |game, week| game_context(college_season, game, week) }
  end

  def game_context(college_season, game, week)
    home = game.home_college_id == college_season.college_id
    opponent_college = home ? game.away_college : game.home_college

    {
      college_season: college_season,
      week: week,
      home: home,
      opponent_college: opponent_college,
      opponent: college_seasons_by_college_id[opponent_college.id]
    }
  end

  def game_json(context)
    opponent_cs = context[:opponent]
    probability = @calculator.win_probability(context[:college_season], opponent_cs, home: context[:home])

    {
      week_number: context[:week].number,
      home: context[:home],
      opponent: college_json(context[:opponent_college]),
      opponent_ratings: ratings_json(opponent_cs),
      opponent_previous_season_record: previous_season_record_json(context[:opponent_college].id),
      opponent_key_players: opponent_cs && key_players_json(opponent_cs),
      win_probability: probability.round(2),
      projection: @calculator.game_projection(probability),
      previous_meetings: previous_meetings_json(context[:college_season].college_id, context[:opponent_college].id)
    }
  end

  def key_players_json(college_season)
    {
      offense: offensive_key_players(college_season).map { |ss| player_json(ss) },
      defense: college_season.best_defensive_players.map { |ss| player_json(ss) }
    }
  end

  # Same as CollegeSeason#best_offensive_players, but guarantees the QB is
  # always included — for the debate, the QB matters more than raw overall
  # rank among offensive skill positions would otherwise suggest.
  def offensive_key_players(college_season, limit: 4)
    qb = college_season.student_seasons
                        .select { |ss| ss.position == "QB" }
                        .max_by { |ss| ss.overall || -1 }
    others = college_season.student_seasons
                            .select { |ss| CollegeSeason::OFFENSE_POSITIONS.include?(ss.position) && ss != qb }
                            .sort_by { |ss| -(ss.overall || -1) }
                            .first(qb ? limit - 1 : limit)
    [ qb, *others ].compact
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

  # Empty until the dynasty has a prior season, but built to "just work"
  # from next season onward without any further changes.
  def previous_meetings_json(college_id_a, college_id_b)
    previous_seasons = @season.dynasty.seasons.where("year < ?", @season.year)
    return [] if previous_seasons.empty?

    games = Game.where(week_id: Week.where(season: previous_seasons).select(:id))
                .where(
                  "(home_college_id = :a AND away_college_id = :b) OR (home_college_id = :b AND away_college_id = :a)",
                  a: college_id_a, b: college_id_b
                )
                .includes(:home_college, :away_college, :college_game_stats, week: :season)

    games.filter_map { |game| previous_meeting_json(game) }.sort_by { |m| m[:year] }
  end

  def previous_meeting_json(game)
    home_stat = game.college_game_stats.find { |s| s.college_id == game.home_college_id }
    away_stat = game.college_game_stats.find { |s| s.college_id == game.away_college_id }
    return nil unless home_stat && away_stat

    {
      year: game.week.season.year,
      home: { name: game.home_college.name, score: home_stat.final_score },
      away: { name: game.away_college.name, score: away_stat.final_score }
    }
  end

  def conference_landscape_json
    conferences = coached_college_seasons.filter_map { |cs| cs.college.conference }.uniq

    conferences.map do |conference|
      others = all_college_seasons.select do |cs|
        cs.college.conference == conference && !coached_college_ids.include?(cs.college_id)
      end

      teams = others.map { |cs| conference_rival_json(cs) }
                    .sort_by { |t| -(t[:vegas_win_total] || 0) }

      { conference: conference, teams: teams }
    end
  end

  def conference_rival_json(college_season)
    {
      college: college_json(college_season.college),
      overall: college_season.overall,
      previous_season_record: previous_season_record_json(college_season.college_id),
      vegas_win_total: @calculator.vegas_win_total(college_season, scheduled_games(college_season))
    }
  end

  def champion_predictions_json
    conferences = coached_college_seasons.filter_map { |cs| cs.college.conference }.uniq

    conferences.map do |conference|
      ranked = strength_ranked.select { |cs, _strength| cs.college.conference == conference }
      favorite = ranked.first
      our_best = ranked.find { |cs, _strength| coached_college_ids.include?(cs.college_id) }

      {
        conference: conference,
        favorite: favorite && strength_entry_json(favorite),
        our_best_shot: our_best && strength_entry_json(our_best, gap_to: favorite&.last)
      }
    end
  end

  def strength_entry_json((college_season, strength), gap_to: nil)
    {
      college: college_json(college_season.college),
      coach: college_season.coach && { id: college_season.coach.id, name: college_season.coach.name },
      team_strength: strength.round(1),
      coached_by_us: coached_college_ids.include?(college_season.college_id),
      previous_season_record: previous_season_record_json(college_season.college_id),
      gap_to_favorite: gap_to && (gap_to - strength).round(1)
    }.compact
  end
end
