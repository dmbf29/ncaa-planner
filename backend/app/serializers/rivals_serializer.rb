# Every played game between two programs that were both run by one of our coaches, across the dynasty's whole history.
# Games are paired by *coach*, not school: a coach who changes schools keeps the same series, and a school with a new
# coach starts a new one. Everything is computed here (records, streaks, superlatives, per-series team and player
# numbers) so the Rivals page only has to lay it out.
class RivalsSerializer
  # Single-game individual stats worth a leaderboard, with how each line is written out.
  PERFORMANCE_CATEGORIES = [
    { key: "passing_yards", label: "Passing yards", column: :passing_yards,
      line: ->(s) { "#{s.passing_completions}/#{s.passing_attempts}, #{s.passing_yards} yds, #{s.passing_tds.to_i} TD, #{s.passing_interceptions.to_i} INT" } },
    { key: "rushing_yards", label: "Rushing yards", column: :rushing_yards,
      line: ->(s) { "#{s.rushing_carries} car, #{s.rushing_yards} yds, #{s.rushing_tds.to_i} TD" } },
    { key: "receiving_yards", label: "Receiving yards", column: :receiving_yards,
      line: ->(s) { "#{s.receiving_receptions} rec, #{s.receiving_yards} yds, #{s.receiving_tds.to_i} TD" } },
    { key: "tackles", label: "Tackles", column: :defense_tackles,
      line: ->(s) { "#{s.defense_tackles} tkl, #{s.defense_tfl.to_i} TFL, #{s.defense_sacks.to_f} sk" } },
    { key: "sacks", label: "Sacks", column: :defense_sacks,
      line: ->(s) { "#{s.defense_sacks.to_f} sk, #{s.defense_tackles.to_i} tkl, #{s.defense_forced_fumbles.to_i} FF" } },
    { key: "interceptions", label: "Interceptions", column: :defense_interceptions,
      line: ->(s) { "#{s.defense_interceptions} INT, #{s.defense_interceptions_yards.to_i} ret yds, #{s.defense_touchdowns.to_i} TD" } }
  ].freeze

  # Team-stat averages shown side by side for each series: [key, label, lower-is-better].
  TEAM_AVERAGES = [
    [ :final_score, "Points", false ],
    [ :total_yards, "Total yards", false ],
    [ :passing_yards, "Passing yards", false ],
    [ :rushing_yards, "Rushing yards", false ],
    [ :first_downs, "First downs", false ],
    [ :turnovers, "Turnovers", true ],
    [ :penalty_yards, "Penalty yards", true ]
  ].freeze

  def initialize(dynasty)
    @dynasty = dynasty
  end

  def as_json
    {
      dynasty: { id: @dynasty.id, name: @dynasty.name },
      summary: summary_json,
      coaches: coaches_json,
      fun_facts: fun_facts,
      all_games: all_games_json,
      rivalries: rivalries.map { |pair| rivalry_json(pair) }
    }
  end

  private

  # ---- Loading ------------------------------------------------------------------------------------------------

  def seasons
    @seasons ||= @dynasty.seasons.order(:year).to_a
  end

  def season_year
    @season_year ||= seasons.to_h { |season| [ season.id, season.year ] }
  end

  def coached_seasons
    @coached_seasons ||= CollegeSeason.where(season_id: seasons.map(&:id)).where.not(coach_id: nil)
                                      .includes(:coach, college: { logo_attachment: :blob }).to_a
  end

  # [season_id, college_id] => the coach running that program that season.
  def coach_by_program
    @coach_by_program ||= coached_seasons.to_h { |cs| [ [ cs.season_id, cs.college_id ], cs.coach ] }
  end

  def weeks
    @weeks ||= Week.where(season_id: seasons.map(&:id)).index_by(&:id)
  end

  def rankings
    @rankings ||= CollegeWeekRanking.where(week_id: weeks.keys).pluck(:week_id, :college_id, :ranking)
                                    .to_h { |week_id, college_id, ranking| [ [ week_id, college_id ], ranking ] }
  end

  # Played games where both programs had one of our coaches, as plain hashes (see #build_game).
  def games
    @games ||= begin
      scope = Game.where(week_id: weeks.keys)
                  .includes(:college_game_stats, home_college: { logo_attachment: :blob }, away_college: { logo_attachment: :blob },
                            offensive_player_of_game: :student, defensive_player_of_game: :student)
      scope.filter_map { |game| build_game(game) }.sort_by { |g| [ g[:year], g[:week_number], g[:id] ] }
    end
  end

  def build_game(game)
    week = weeks[game.week_id]
    year = season_year[week.season_id]
    home_coach = coach_by_program[[ week.season_id, game.home_college_id ]]
    away_coach = coach_by_program[[ week.season_id, game.away_college_id ]]
    return nil unless home_coach && away_coach

    stats = game.college_game_stats.index_by(&:college_id)
    home_stat = stats[game.home_college_id]
    away_stat = stats[game.away_college_id]
    return nil if home_stat&.final_score.nil? || away_stat&.final_score.nil?

    sides = [
      side_json(game.home_college, home_coach, home_stat, rankings[[ week.id, game.home_college_id ]]),
      side_json(game.away_college, away_coach, away_stat, rankings[[ week.id, game.away_college_id ]])
    ]
    winner = sides.max_by { |s| s[:score] } unless home_stat.final_score == away_stat.final_score
    loser = (sides - [ winner ]).first if winner

    {
      id: game.id, year: year, week_number: week.number, week_name: week.name, time: game.time,
      label: label_for(game, week), cfp_round: game.cfp_round, bowl_name: game.bowl_name,
      conference_championship: week.conference_championship,
      home: sides[0], away: sides[1],
      winner_coach_id: winner&.dig(:coach_id), loser_coach_id: loser&.dig(:coach_id),
      margin: (winner ? winner[:score] - loser[:score] : 0),
      total_points: sides.sum { |s| s[:score] },
      overtime: sides.any? { |s| s[:overtime_points].to_i.positive? },
      comeback: comeback_for(sides, winner),
      upset: upset?(winner, loser),
      both_ranked: sides.all? { |s| s[:rank] },
      offensive_player_of_game: pog_json(game.offensive_player_of_game, game.offensive_player_stat_line),
      defensive_player_of_game: pog_json(game.defensive_player_of_game, game.defensive_player_stat_line)
    }
  end

  def side_json(college, coach, stat, rank)
    {
      coach_id: coach.id, coach_name: coach.name,
      college: { id: college.id, name: college.name, abbrev: college.abbrev,
                 logo_url: (college.logo.url if college.logo.attached?) },
      score: stat.final_score, rank: rank,
      quarters: [ stat.points_in_quarter_1, stat.points_in_quarter_2, stat.points_in_quarter_3, stat.points_in_quarter_4 ],
      overtime_points: stat.points_in_overtime,
      stat: stat
    }
  end

  def label_for(game, week)
    return cfp_label(game.cfp_round) if game.cfp_round
    return game.bowl_name if game.bowl_name.present?
    return "Conference Championship" if week.conference_championship

    nil
  end

  def cfp_label(round)
    { "first_round" => "CFP First Round", "quarterfinal" => "CFP Quarterfinal", "semifinal" => "CFP Semifinal",
      "championship" => "National Championship" }[round.to_s]
  end

  # The biggest deficit the winner erased at the end of any of the first three quarters (nil when they never trailed).
  def comeback_for(sides, winner)
    return nil unless winner

    other = (sides - [ winner ]).first
    worst = 0
    (0..2).each do |i|
      next if winner[:quarters][0..i].any?(&:nil?) || other[:quarters][0..i].any?(&:nil?)

      deficit = other[:quarters][0..i].sum - winner[:quarters][0..i].sum
      worst = [ worst, deficit ].max
    end
    worst.positive? ? worst : nil
  end

  # A ranked loser beaten by an unranked or lower-ranked winner.
  def upset?(winner, loser)
    return false unless winner && loser && loser[:rank]

    winner[:rank].nil? || winner[:rank] > loser[:rank]
  end

  def pog_json(student_season, stat_line)
    return nil unless student_season

    { name: student_season.student.name, position: student_season.position, stat_line: stat_line, student_season_id: student_season.id }
  end

  # ---- Public shapes ------------------------------------------------------------------------------------------

  # The game as the page lists it: both sides' scoreboard line, the headline team numbers, and the players of the game.
  def game_json(game)
    game.except(:home, :away).merge(
      home: public_side(game[:home]),
      away: public_side(game[:away])
    )
  end

  def public_side(side)
    stat = side[:stat]
    side.except(:stat, :quarters).merge(
      quarters: side[:quarters],
      stats: {
        total_yards: stat.total_yards, passing_yards: stat.passing_yards, rushing_yards: stat.rushing_yards,
        turnovers: stat.turnovers, first_downs: stat.first_downs
      }
    )
  end

  def side_of(game, coach_id)
    [ game[:home], game[:away] ].find { |s| s[:coach_id] == coach_id }
  end

  # ---- Coaches ------------------------------------------------------------------------------------------------

  def coach_records
    @coach_records ||= begin
      records = Hash.new { |h, k| h[k] = { wins: 0, losses: 0, ties: 0, points_for: 0, points_against: 0, games: [] } }
      games.each do |game|
        [ game[:home], game[:away] ].each do |side|
          other = side.equal?(game[:home]) ? game[:away] : game[:home]
          rec = records[side[:coach_id]]
          rec[:points_for] += side[:score]
          rec[:points_against] += other[:score]
          rec[:games] << game
          if game[:winner_coach_id].nil? then rec[:ties] += 1
          elsif game[:winner_coach_id] == side[:coach_id] then rec[:wins] += 1
          else rec[:losses] += 1
          end
        end
      end
      records
    end
  end

  def coaches_json
    all = coached_seasons.map(&:coach).uniq
    all.map do |coach|
      rec = coach_records[coach.id]
      played = rec[:wins] + rec[:losses] + rec[:ties]
      {
        id: coach.id, name: coach.name,
        schools: schools_for(coach),
        wins: rec[:wins], losses: rec[:losses], ties: rec[:ties], games: played,
        win_pct: (played.positive? ? ((rec[:wins] + rec[:ties] / 2.0) / played).round(3) : nil),
        points_for: rec[:points_for], points_against: rec[:points_against],
        avg_margin: (played.positive? ? ((rec[:points_for] - rec[:points_against]) / played.to_f).round(1) : nil),
        ranked_wins: rec[:games].count { |g| g[:winner_coach_id] == coach.id && g[:both_ranked] },
        playoff_wins: rec[:games].count { |g| g[:winner_coach_id] == coach.id && g[:cfp_round] },
        title_game_wins: rec[:games].count { |g| g[:winner_coach_id] == coach.id && g[:cfp_round] == "championship" },
        overtime_record: record_string(rec[:games].select { |g| g[:overtime] }, coach.id),
        best_streak: best_streak(rec[:games], coach.id)
      }
    end.sort_by { |c| [ -(c[:win_pct] || -1), -c[:games], c[:name] ] }
  end

  # [{college:, years:}] for each school the coach has run, oldest first.
  def schools_for(coach)
    coached_seasons.select { |cs| cs.coach_id == coach.id }
                   .sort_by { |cs| season_year[cs.season_id] }
                   .chunk_while { |a, b| a.college_id == b.college_id }
                   .map do |run|
      college = run.first.college
      { college: { id: college.id, name: college.name, abbrev: college.abbrev, logo_url: (college.logo.url if college.logo.attached?) },
        years: run.map { |cs| season_year[cs.season_id] } }
    end
  end

  def record_string(list, coach_id)
    wins = list.count { |g| g[:winner_coach_id] == coach_id }
    ties = list.count { |g| g[:winner_coach_id].nil? }
    "#{wins}-#{list.size - wins - ties}#{"-#{ties}" if ties.positive?}"
  end

  def best_streak(list, coach_id)
    best = run = 0
    list.each do |game|
      run = game[:winner_coach_id] == coach_id ? run + 1 : 0
      best = [ best, run ].max
    end
    best
  end

  # ---- Series -------------------------------------------------------------------------------------------------

  # [[coach_a, coach_b, [games]]] with the pair ordered by name; busiest series first.
  def rivalries
    @rivalries ||= games.group_by { |g| [ g[:home][:coach_id], g[:away][:coach_id] ].sort }
                        .map { |(a, b), list| order_pair(a, b, list) }
                        .sort_by { |pair| [ -pair[2].size, pair[0][:name] ] }
  end

  def order_pair(id_a, id_b, list)
    coaches = [ id_a, id_b ].map { |id| coached_seasons.find { |cs| cs.coach_id == id }.coach }
    coaches.sort_by!(&:name)
    [ { id: coaches[0].id, name: coaches[0].name }, { id: coaches[1].id, name: coaches[1].name }, list ]
  end

  def rivalry_json(pair)
    a, b, list = pair
    ids = [ a[:id], b[:id] ]
    wins = ids.to_h { |id| [ id, list.count { |g| g[:winner_coach_id] == id } ] }
    ties = list.count { |g| g[:winner_coach_id].nil? }
    decided = list.reject { |g| g[:winner_coach_id].nil? }

    {
      key: ids.join("-"),
      coaches: ids.map { |id| series_coach_json(id, list, wins) },
      games_played: list.size,
      ties: ties,
      total_points: list.sum { |g| g[:total_points] },
      current_streak: current_streak(list),
      longest_streaks: ids.to_h { |id| [ id, best_streak(list, id) ] },
      first_meeting: game_json(list.first),
      last_meeting: game_json(list.last),
      superlatives: superlatives(list),
      flags: flags(list),
      team_averages: team_averages(list, ids),
      performances: performances(list, ids),
      games: list.map { |g| game_json(g) }
    }
  end

  # The whole history as one pseudo-series: every user-vs-user game, with the same moments, flags and top performances.
  def all_games_json
    {
      games_played: games.size,
      total_points: games.sum { |g| g[:total_points] },
      superlatives: superlatives(games),
      flags: flags(games),
      performances: performances(games, nil),
      games: games.map { |g| game_json(g) }
    }
  end

  def superlatives(list)
    decided = list.reject { |g| g[:winner_coach_id].nil? }
    {
      biggest_win: superlative(decided.max_by { |g| g[:margin] }),
      closest_game: superlative(list.min_by { |g| [ g[:margin], -g[:total_points] ] }),
      highest_scoring: superlative(list.max_by { |g| g[:total_points] }),
      lowest_scoring: superlative(list.min_by { |g| g[:total_points] })
    }
  end

  def flags(list)
    {
      overtime: list.count { |g| g[:overtime] },
      both_ranked: list.count { |g| g[:both_ranked] },
      postseason: list.count { |g| g[:label] },
      comebacks: list.count { |g| g[:comeback] },
      one_score_games: list.count { |g| g[:margin] <= 8 },
      shutouts: list.count { |g| [ g[:home][:score], g[:away][:score] ].min.zero? }
    }
  end

  def superlative(game)
    game && game_json(game)
  end

  def series_coach_json(coach_id, list, wins)
    sides = list.map { |g| side_of(g, coach_id) }
    home_games = list.select { |g| g[:home][:coach_id] == coach_id }
    away_games = list - home_games
    margin_total = list.sum { |g| side_of(g, coach_id)[:score] - (g[:total_points] - side_of(g, coach_id)[:score]) }
    {
      id: coach_id,
      wins: wins[coach_id],
      points_for: sides.sum { |s| s[:score] },
      avg_margin: (margin_total / list.size.to_f).round(1),
      home: { wins: home_games.count { |g| g[:winner_coach_id] == coach_id }, games: home_games.size },
      away: { wins: away_games.count { |g| g[:winner_coach_id] == coach_id }, games: away_games.size },
      schools: sides.map { |s| s[:college] }.uniq { |c| c[:id] },
      player_of_game: {
        offense: list.count { |g| side_of(g, coach_id) && pog_side?(g, :offensive_player_of_game, coach_id) },
        defense: list.count { |g| pog_side?(g, :defensive_player_of_game, coach_id) }
      }
    }
  end

  # Whether the game's player of the game on that side played for this coach's program.
  def pog_side?(game, key, coach_id)
    pog = game[key]
    return false unless pog

    @pog_college ||= StudentSeason.where(id: games.flat_map { |g| [ g[:offensive_player_of_game], g[:defensive_player_of_game] ] }.compact.map { |p| p[:student_season_id] })
                                  .joins(:college_season).pluck(:id, "college_seasons.college_id", "college_seasons.season_id")
                                  .to_h { |id, college_id, season_id| [ id, [ college_id, season_id ] ] }
    college_id, season_id = @pog_college[pog[:student_season_id]]
    coach_by_program[[ season_id, college_id ]]&.id == coach_id
  end

  def current_streak(list)
    last = list.reverse.find { |g| g[:winner_coach_id] }
    return nil unless last

    length = list.reverse.take_while { |g| g[:winner_coach_id] == last[:winner_coach_id] }.size
    { coach_id: last[:winner_coach_id], length: length }
  end

  # Per-coach averages across the series for the numbers in TEAM_AVERAGES, plus third-down conversion rate.
  def team_averages(list, ids)
    rows = TEAM_AVERAGES.map do |key, label, lower_better|
      values = ids.to_h do |id|
        nums = list.filter_map { |g| side_of(g, id)[:stat].public_send(key) }
        [ id, (nums.sum / nums.size.to_f).round(1) ]
      rescue ZeroDivisionError
        [ id, nil ]
      end
      { key: key, label: label, lower_is_better: lower_better, values: values }
    end
    third = ids.to_h do |id|
      stats = list.map { |g| side_of(g, id)[:stat] }
      attempts = stats.sum { |s| s.third_down_attempts.to_i }
      [ id, (attempts.positive? ? (100.0 * stats.sum { |s| s.third_down_conversions.to_i } / attempts).round(1) : nil) ]
    end
    rows << { key: "third_down_pct", label: "3rd down %", lower_is_better: false, values: third }
    rows
  end

  # ---- Player performances ------------------------------------------------------------------------------------

  def game_stats_by_game
    @game_stats_by_game ||= StudentGameStat.where(game_id: games.map { |g| g[:id] })
                                           .includes(student_season: %i[student college_season]).group_by(&:game_id)
  end

  def performances(list, ids)
    PERFORMANCE_CATEGORIES.filter_map do |category|
      entries = list.flat_map do |game|
        (game_stats_by_game[game[:id]] || []).filter_map do |stat|
          value = stat.public_send(category[:column])
          next unless value&.positive?

          college_season = stat.student_season.college_season
          coach = coach_by_program[[ college_season.season_id, college_season.college_id ]]
          next unless coach && (ids.nil? || ids.include?(coach.id))

          { value: value, coach_id: coach.id, player: stat.student_season.student.name, position: stat.student_season.position,
            college: [ game[:home], game[:away] ].find { |s| s[:college][:id] == college_season.college_id }[:college],
            opponent: [ game[:home], game[:away] ].find { |s| s[:college][:id] != college_season.college_id }[:college],
            year: game[:year], game_id: game[:id], line: category[:line].call(stat) }
        end
      end
      next if entries.empty?

      { key: category[:key], label: category[:label], top: entries.sort_by { |e| -e[:value] }.first(3) }
    end
  end

  # ---- Whole-history views --------------------------------------------------------------------------------------

  def summary_json
    {
      games: games.size,
      series: rivalries.size,
      seasons: games.map { |g| g[:year] }.uniq.size,
      first_year: games.first&.dig(:year),
      last_year: games.last&.dig(:year),
      total_points: games.sum { |g| g[:total_points] },
      avg_margin: average(games.map { |g| g[:margin] }),
      avg_home_score: average(games.map { |g| g[:home][:score] }),
      avg_away_score: average(games.map { |g| g[:away][:score] }),
      avg_interceptions: average(games.map { |g| [ g[:home], g[:away] ].sum { |side| side[:stat].interceptions_thrown.to_i } }),
      overtime_games: games.count { |g| g[:overtime] },
      cfp_games: games.count { |g| g[:cfp_round] },
      ranked_matchups: games.count { |g| g[:both_ranked] },
      postseason_games: games.count { |g| g[:label] },
      upsets: games.count { |g| g[:upset] }
    }
  end

  def average(values)
    values.empty? ? nil : (values.sum / values.size.to_f).round(1)
  end

  def fun_facts
    return [] if games.empty?

    decided = games.reject { |g| g[:winner_coach_id].nil? }
    facts = []
    add = lambda do |id, title, value, detail, game = nil|
      facts << { id: id, title: title, value: value, detail: detail, game: (game_json(game) if game) }
    end

    if (g = decided.max_by { |g| g[:margin] })
      add.call("blowout", "Biggest blowout", "#{g[:margin]} points", "#{matchup_text(g)} in #{g[:year]}", g)
    end
    if (g = games.min_by { |g| [ g[:margin], g[:year] ] })
      add.call("closest", "Closest game", g[:margin].zero? ? "A tie" : "#{g[:margin]} #{g[:margin] == 1 ? 'point' : 'points'}", "#{matchup_text(g)} in #{g[:year]}", g)
    end
    if (g = games.max_by { |g| g[:total_points] })
      add.call("shootout", "Highest-scoring shootout", "#{g[:total_points]} points", "#{matchup_text(g)} in #{g[:year]}", g)
    end
    if (g = games.min_by { |g| g[:total_points] })
      add.call("slugfest", "Lowest-scoring slugfest", "#{g[:total_points]} points", "#{matchup_text(g)} in #{g[:year]}", g)
    end
    if (g = games.select { |g| g[:comeback] }.max_by { |g| g[:comeback] })
      winner = side_of(g, g[:winner_coach_id])
      loser = side_of(g, g[:loser_coach_id])
      add.call("comeback", "Greatest comeback", "#{g[:comeback]}-point hole",
               "#{winner[:coach_name]} (#{winner[:college][:name]}) erased it against #{loser[:coach_name]} (#{loser[:college][:name]}) in #{g[:year]}", g)
    end
    if (g = decided.select { |g| g[:upset] }.max_by { |g| upset_size(g) })
      winner = side_of(g, g[:winner_coach_id])
      loser = side_of(g, g[:loser_coach_id])
      add.call("upset", "Biggest upset", "##{loser[:rank]} falls", "#{winner[:coach_name]}#{" (##{winner[:rank]})" if winner[:rank]} toppled #{loser[:coach_name]} in #{g[:year]}", g)
    end
    if (pair = rivalries.first)
      add.call("busiest", "Most-played rivalry", "#{pair[2].size} games", "#{pair[0][:name]} vs #{pair[1][:name]}")
    end
    if (item = longest_streak_overall)
      add.call("streak", "Longest series win streak", "#{item[:length]} straight", "#{item[:winner]} over #{item[:loser]}")
    end
    if (item = most_one_sided_series)
      add.call("one_sided", "Most one-sided series", item[:record], "#{item[:winner]} over #{item[:loser]}")
    end
    ot = games.count { |g| g[:overtime] }
    add.call("overtime", "Overtime thrillers", ot.to_s, "Games that needed extra time") if ot.positive?
    title = games.count { |g| g[:cfp_round] == "championship" }
    add.call("title_games", "National title games between users", title.to_s, "Our coaches meeting for the whole thing") if title.positive?
    facts
  end

  def matchup_text(game)
    winner_id = game[:winner_coach_id]
    first, second = winner_id ? [ side_of(game, winner_id), side_of(game, game[:loser_coach_id]) ] : [ game[:home], game[:away] ]
    "#{first[:coach_name]} (#{first[:college][:name]}) #{first[:score]}, #{second[:coach_name]} (#{second[:college][:name]}) #{second[:score]}"
  end

  # How far a ranked loser fell to an unranked (treated as #26) or lower-ranked winner.
  def upset_size(game)
    winner = side_of(game, game[:winner_coach_id])
    loser = side_of(game, game[:loser_coach_id])
    (winner[:rank] || 26) - loser[:rank]
  end

  def longest_streak_overall
    rivalries.flat_map do |a, b, list|
      [ a, b ].map do |coach|
        other = coach.equal?(a) ? b : a
        { length: best_streak(list, coach[:id]), winner: coach[:name], loser: other[:name] }
      end
    end.max_by { |s| s[:length] }.then { |s| s if s && s[:length] > 1 }
  end

  def most_one_sided_series
    rivalries.select { |_, _, list| list.size >= 3 }.map do |a, b, list|
      wa = list.count { |g| g[:winner_coach_id] == a[:id] }
      wb = list.count { |g| g[:winner_coach_id] == b[:id] }
      winner, loser, w, l = wa >= wb ? [ a, b, wa, wb ] : [ b, a, wb, wa ]
      { gap: w - l, ratio: (w.to_f / list.size), record: "#{w}-#{l}", winner: winner[:name], loser: loser[:name] }
    end.max_by { |s| [ s[:ratio], s[:gap] ] }.then { |s| s if s && s[:gap] > 1 }
  end
end
