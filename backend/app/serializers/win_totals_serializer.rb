# Preseason "Vegas win total" episode: a projected win total (see
# WinTotals::Calculator) for each of our coached teams, plus everything the
# two hosts need to debate it — full schedule, home/away splits, opponent
# ratings and key players game-by-game, and past head-to-head results once
# the dynasty has more than one season on the books. Each team also carries a
# win-total outlook (the chance of every win total) and a hot seat thermometer
# for its coach (see WinTotals::HotSeat).
class WinTotalsSerializer
  def initialize(season)
    @season = season
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

  # Built lazily because the overall-to-room offset is measured from this
  # season's college_seasons (see WinTotals::Calculator.overall_offset_for).
  def calculator
    @calculator ||= WinTotals::Calculator.new(overall_offset: WinTotals::Calculator.overall_offset_for(all_college_seasons))
  end

  def focus_json
    {
      instructions: "This is a Vegas-style win-totals debate for our #{coached_college_seasons.size} coached " \
                    "teams heading into the #{@season.year} season — no games have been played yet. Each team " \
                    "has a projected win total ending in .5. One host argues the OVER, the other argues the " \
                    "UNDER, using strength of schedule, home/away splits, and the opponent-by-opponent detail " \
                    "below as ammunition. Each team ends with a hot seat check on its head coach: how safe his " \
                    "job is if the team hits the number, and what happens if it doesn't."
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
    @strength_ranked ||= all_college_seasons.filter_map { |cs| [ cs, calculator.team_strength(cs) ] }
                                             .select { |_cs, strength| strength }
                                             .sort_by { |_cs, strength| -strength }
  end

  def team_json(college_season)
    games = scheduled_games(college_season)
    schedule = games.map { |g| game_json(g) }
    probabilities = games.map { |g| calculator.win_probability(g[:college_season], g[:opponent], home: g[:home]) }
    distribution = calculator.win_distribution(probabilities)
    line = calculator.vegas_win_total(college_season, games)

    {
      college: college_json(college_season.college, college_season.conference),
      coach: { id: college_season.coach.id, name: college_season.coach.name },
      ratings: ratings_json(college_season),
      previous_season_record: previous_season_record_json(college_season.college_id),
      vegas_win_total: line,
      outlook: outlook_json(line, probabilities, distribution),
      hot_seat: hot_seat_json(college_season, line, schedule, distribution),
      schedule_summary: schedule_summary_json(schedule),
      key_players: key_players_json(college_season),
      position_group_averages: college_season.position_group_averages.compact,
      schedule: schedule
    }
  end

  # The chance of landing on each side of the line, from the per-game odds.
  # `bowl_eligible` is six or more wins; a losing season has more losses than
  # wins.
  def outlook_json(line, probabilities, distribution)
    return nil if line.nil?

    games = probabilities.size
    {
      expected_wins: probabilities.sum.round(1),
      chance_over: distribution.each_with_index.sum { |chance, wins| wins > line ? chance : 0.0 }.round(2),
      chance_under: distribution.each_with_index.sum { |chance, wins| wins < line ? chance : 0.0 }.round(2),
      chance_bowl_eligible: distribution.each_with_index.sum { |chance, wins| wins >= 6 ? chance : 0.0 }.round(2),
      chance_losing_season: distribution.each_with_index.sum { |chance, wins| wins * 2 < games ? chance : 0.0 }.round(2)
    }
  end

  def hot_seat_json(college_season, line, schedule, distribution)
    games = schedule.map do |game|
      { week_number: game[:week_number], home: game[:home], opponent: game[:opponent][:name],
        projection: game[:projection], win_probability: game[:win_probability] }
    end
    WinTotals::HotSeat.new(
      coach: college_season.coach, line: line, games: games, distribution: distribution,
      calculator: calculator, bye_week_number: first_bye_week_number(college_season)
    ).call
  end

  # The first real bye week (week 0 is the preseason slot, not a bye).
  def first_bye_week_number(college_season)
    return nil if college_season.bye_week_ids.blank?

    Week.where(id: college_season.bye_week_ids).where("number > 0").minimum(:number)
  end

  def schedule_summary_json(schedule)
    {
      likely_wins: schedule.count { |g| g[:projection] == :likely_win },
      likely_losses: schedule.count { |g| g[:projection] == :likely_loss },
      coin_flips: schedule.count { |g| g[:projection] == :coin_flip }
    }
  end

  def college_json(college, conference)
    { id: college.id, name: college.name, conference: conference }
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
    probability = calculator.win_probability(context[:college_season], opponent_cs, home: context[:home])

    {
      week_number: context[:week].number,
      home: context[:home],
      opponent: college_json(context[:opponent_college], opponent_cs&.conference),
      opponent_ratings: ratings_json(opponent_cs),
      opponent_previous_season_record: previous_season_record_json(context[:opponent_college].id),
      opponent_key_players: opponent_cs && key_players_json(opponent_cs),
      win_probability: probability.round(2),
      projection: calculator.game_projection(probability),
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
    conferences = coached_college_seasons.filter_map(&:conference).uniq

    conferences.map do |conference|
      others = all_college_seasons.select do |cs|
        cs.conference == conference && !coached_college_ids.include?(cs.college_id)
      end

      teams = others.map { |cs| conference_rival_json(cs) }
                    .sort_by { |t| [ -(t[:vegas_win_total] || 0), -(t[:power_rating] || 0) ] }

      { conference: conference, teams: teams }
    end
  end

  # A win total is only meaningful with (nearly) the full schedule on file; a
  # rival whose schedule hasn't been uploaded has just its games against our
  # coached teams, which would produce a nonsense line like 0.5. Below this
  # many games the rival gets no line, only a power rating (which needs just a
  # roster) so the hosts can still place them.
  MIN_GAMES_FOR_LINE = 10

  def conference_rival_json(college_season)
    games = scheduled_games(college_season)
    strength = calculator.team_strength(college_season)
    {
      college: college_json(college_season.college, college_season.conference),
      overall: college_season.overall,
      power_rating: strength&.round(1),
      previous_season_record: previous_season_record_json(college_season.college_id),
      scheduled_games: games.size,
      vegas_win_total: games.size >= MIN_GAMES_FOR_LINE ? calculator.vegas_win_total(college_season, games) : nil
    }
  end

  def champion_predictions_json
    conferences = coached_college_seasons.filter_map(&:conference).uniq

    conferences.map do |conference|
      ranked = strength_ranked.select { |cs, _strength| cs.conference == conference }
      top = ranked.first
      our_best_index = ranked.index { |cs, _strength| coached_college_ids.include?(cs.college_id) }
      our_best = our_best_index && ranked[our_best_index]

      {
        conference: conference,
        championship_game: championship_game_json(ranked.first(2)),
        # Only worth a mention when none of ours made the title game.
        our_best_shot: our_best && our_best_index >= CHAMPIONSHIP_GAME_TEAMS ? strength_entry_json(our_best, gap_to: top&.last).merge(rank: our_best_index + 1) : nil
      }
    end
  end

  CHAMPIONSHIP_GAME_TEAMS = 2

  # The two strongest teams in the conference meet in the title game (there
  # are no full conference schedules for the rest of the league, so power
  # rating stands in for the standings). The favorite is whoever the odds
  # favor at a neutral site.
  def championship_game_json(finalists)
    return nil if finalists.size < CHAMPIONSHIP_GAME_TEAMS

    (favorite_cs, favorite_strength), (underdog_cs, underdog_strength) = finalists
    chance = calculator.win_probability(favorite_cs, underdog_cs, home: nil)
    {
      teams: finalists.map { |entry| strength_entry_json(entry) },
      favorite: strength_entry_json([ favorite_cs, favorite_strength ]),
      underdog: strength_entry_json([ underdog_cs, underdog_strength ]),
      favorite_chance: chance.round(2),
      edge: championship_edge(chance)
    }
  end

  def championship_edge(chance)
    return "clear" if chance >= 0.75
    return "slight" if chance >= 0.58

    "pick_em"
  end

  def strength_entry_json((college_season, strength), gap_to: nil)
    {
      college: college_json(college_season.college, college_season.conference),
      coach: college_season.coach && { id: college_season.coach.id, name: college_season.coach.name },
      team_strength: strength.round(1),
      coached_by_us: coached_college_ids.include?(college_season.college_id),
      previous_season_record: previous_season_record_json(college_season.college_id),
      gap_to_favorite: gap_to && (gap_to - strength).round(1)
    }.compact
  end
end
