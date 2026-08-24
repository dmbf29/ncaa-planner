# Midseason "report card" episode: the app deliberately does NOT compute a
# letter grade anywhere in here — that's the hosts' call. This just gathers
# the evidence they'd need to argue one: results so far, whether the team is
# ahead of or behind the pace implied by the preseason Vegas number (see
# WinTotals::Calculator, reused here so both shows agree on what a game's
# pregame lean was), any win/loss that defied that pregame lean, season
# team stats (both totals and per-game, since a team coming off a bye has
# played fewer games than one that hasn't), conference standing, and the
# remaining schedule for the closing "how to improve" segment.
class MidseasonReportCardSerializer
  OFFENSE_STAT_COLUMNS = %i[
    points_scored total_offensive_yards passing_yards passing_touchdowns
    rushing_yards rushing_touchdowns first_downs
  ].freeze

  DEFENSE_STAT_COLUMNS = %i[
    points_allowed total_yards_allowed passing_yards_allowed rushing_yards_allowed
    defensive_sacks fumble_recoveries defensive_interceptions
  ].freeze

  # Whether more or less of a stat is good — "allowed" stats rank ascending
  # (fewest points/yards given up is best), everything else ranks descending.
  STAT_DIRECTIONS = {
    points_scored: :higher, total_offensive_yards: :higher, yards_per_play: :higher,
    passing_yards: :higher, passing_touchdowns: :higher, rushing_yards: :higher,
    rushing_touchdowns: :higher, first_downs: :higher,
    points_allowed: :lower, total_yards_allowed: :lower, passing_yards_allowed: :lower,
    rushing_yards_allowed: :lower,
    defensive_sacks: :higher, fumble_recoveries: :higher, defensive_interceptions: :higher
  }.freeze

  def initialize(season)
    @season = season
    @calculator = WinTotals::Calculator.new
  end

  def as_json
    {
      focus: focus_json,
      season: { id: @season.id, year: @season.year, dynasty: @season.dynasty.name },
      teams: coached_college_seasons.map { |cs| team_json(cs) }
    }
  end

  private

  def focus_json
    {
      instructions: "Midseason report cards for our #{coached_college_seasons.size} coached teams. Each host " \
                    "gives their own letter grade (A+ to F) for each team based on the evidence below — the app " \
                    "does not compute a grade, and the hosts do not have to agree with each other."
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

  def all_college_seasons
    @all_college_seasons ||= @season.college_seasons.includes(:college, student_seasons: :student).to_a
  end

  def college_seasons_by_college_id
    @college_seasons_by_college_id ||= all_college_seasons.index_by(&:college_id)
  end

  def college_seasons_by_conference
    @college_seasons_by_conference ||= all_college_seasons.group_by { |cs| cs.college.conference }
  end

  def team_json(college_season)
    games = scheduled_games(college_season)
    played_games, remaining_games = games.partition { |g| g[:played] }
    record = record_json(played_games)

    {
      college: college_json(college_season.college),
      coach: { id: college_season.coach.id, name: college_season.coach.name },
      ratings: ratings_json(college_season),
      record: record,
      record_note: record_note(college_season, record),
      conference_standing: conference_standing_json(college_season),
      vegas_context: vegas_context_json(college_season, games, played_games),
      notable_results: notable_results_json(played_games),
      team_stats: team_stats_json(college_season, played_games.size),
      played_schedule: played_games.map { |g| played_game_json(g) },
      remaining_schedule: remaining_games.map { |g| remaining_game_json(g) }
    }
  end

  def college_json(college)
    { id: college.id, name: college.name, conference: college.conference }
  end

  def ratings_json(college_season)
    return nil unless college_season

    { overall: college_season.overall, offense: college_season.offense, defense: college_season.defense }
  end

  # Derived directly from recorded game results rather than
  # college_season.wins/losses — that column is maintained separately (via
  # a standings screenshot commit) and can lag behind box scores that have
  # already been entered. See record_note.
  def record_json(played_games)
    wins = played_games.count { |g| g[:result][:won] }
    losses = played_games.size - wins
    conference_games = played_games.select { |g| conference_game?(g) }
    conference_wins = conference_games.count { |g| g[:result][:won] }
    conference_losses = conference_games.size - conference_wins

    { wins: wins, losses: losses, conference_wins: conference_wins, conference_losses: conference_losses }
  end

  def conference_game?(game)
    team_conference = game[:college_season].college.conference
    team_conference.present? && team_conference == game[:opponent_college].conference
  end

  def record_note(college_season, derived_record)
    return nil if college_season.wins.nil? && college_season.losses.nil?
    return nil if college_season.wins == derived_record[:wins] && college_season.losses == derived_record[:losses]

    "Heads up: the official conference standings still show #{college_season.wins}-#{college_season.losses} for " \
      "this team — the record and conference standing here are calculated straight from recorded games, so they " \
      "may be a result or two ahead of what's officially posted."
  end

  def conference_standing_json(college_season)
    conference = college_season.college.conference
    return nil unless conference

    ranked = college_seasons_by_conference.fetch(conference, [])
                                           .sort_by { |cs| [ -win_pct(cs.conference_wins, cs.conference_losses), -win_pct(cs.wins, cs.losses) ] }
    { rank: ranked.index(college_season) + 1, of: ranked.size }
  end

  def win_pct(wins, losses)
    total = wins.to_i + losses.to_i
    return 0.0 if total.zero?

    wins.to_f / total
  end

  # Every regular-season game (week 0 is preseason/exhibition, so it's
  # excluded same as the other broadcast serializers), tagged with whether
  # it's been played and, if so, the result.
  def scheduled_games(college_season)
    college_season.games
                   .includes(:home_college, :away_college, :college_game_stats, week: :season)
                   .map { |game| [ game, game.week ] }
                   .reject { |_game, week| week.number.zero? }
                   .sort_by { |_game, week| week.number }
                   .map { |game, week| game_context(college_season, game, week) }
  end

  def game_context(college_season, game, week)
    home = game.home_college_id == college_season.college_id
    opponent_college = home ? game.away_college : game.home_college
    result = game_result(game, college_season.college_id)

    {
      college_season: college_season,
      week: week,
      home: home,
      opponent_college: opponent_college,
      opponent: college_seasons_by_college_id[opponent_college.id],
      played: result.present?,
      result: result
    }
  end

  def game_result(game, college_id)
    stats = game.college_game_stats.index_by(&:college_id)
    team_stat = stats[college_id]
    opponent_stat = stats.values.find { |s| s.college_id != college_id }
    return nil unless team_stat&.final_score && opponent_stat&.final_score

    { won: team_stat.final_score > opponent_stat.final_score, team_score: team_stat.final_score, opponent_score: opponent_stat.final_score }
  end

  def pregame_projection(game)
    probability = @calculator.win_probability(game[:college_season], game[:opponent], home: game[:home])
    @calculator.game_projection(probability)
  end

  # Recomputes the same number WinTotalsSerializer would have published
  # preseason (team ratings don't change once the season starts), then
  # compares actual results through games played against what the pregame
  # leans on those same games would have expected, plus a live re-projection
  # for the rest of the way.
  def vegas_context_json(college_season, all_games, played_games)
    wins_so_far = played_games.count { |g| g[:result][:won] }
    expected_through_played = played_games.sum { |g| @calculator.win_probability(college_season, g[:opponent], home: g[:home]) }
    remaining_games = all_games - played_games
    remaining_expected = remaining_games.sum { |g| @calculator.win_probability(college_season, g[:opponent], home: g[:home]) }

    {
      preseason_win_total: @calculator.vegas_win_total(college_season, all_games),
      games_played: played_games.size,
      wins_so_far: wins_so_far,
      expected_wins_through_played_games: expected_through_played.round(2),
      pace_differential: (wins_so_far - expected_through_played).round(2),
      updated_projected_wins: (wins_so_far + remaining_expected).round(2)
    }
  end

  # A win the preseason numbers said was more likely a loss, or a loss the
  # preseason numbers said was more likely a win.
  def notable_results_json(played_games)
    signature_wins = played_games.select { |g| g[:result][:won] && pregame_projection(g) == :likely_loss }
    bad_losses = played_games.select { |g| !g[:result][:won] && pregame_projection(g) == :likely_win }

    {
      signature_wins: signature_wins.map { |g| notable_game_json(g) },
      bad_losses: bad_losses.map { |g| notable_game_json(g) }
    }
  end

  def notable_game_json(game)
    {
      week_number: game[:week].number,
      home: game[:home],
      opponent: college_json(game[:opponent_college]),
      score: { team: game[:result][:team_score], opponent: game[:result][:opponent_score] }
    }
  end

  def team_stats_json(college_season, games_played)
    {
      games_played: games_played,
      offense: stat_group_json(college_season, OFFENSE_STAT_COLUMNS, games_played)
                 .merge(yards_per_play: rate_stat_json(college_season)),
      defense: stat_group_json(college_season, DEFENSE_STAT_COLUMNS, games_played)
    }
  end

  def stat_group_json(college_season, columns, games_played)
    columns.index_with do |column|
      total = college_season.public_send(column)
      next nil if total.nil?

      {
        total: total,
        per_game: games_played.positive? ? (total.to_f / games_played).round(1) : nil,
        conference_rank: conference_stat_rank(college_season, column)
      }
    end
  end

  def rate_stat_json(college_season)
    value = college_season.yards_per_play
    return nil if value.nil?

    { rate: value, conference_rank: conference_stat_rank(college_season, :yards_per_play) }
  end

  # Ranked on a per-game basis (total ÷ games actually played) rather than
  # season totals, so a team that's had a bye isn't penalized against one
  # that hasn't — same reasoning as the per-game figures shown alongside.
  def conference_stat_rank(college_season, column)
    conference = college_season.college.conference
    return nil unless conference

    leaderboard = conference_stat_leaderboard(conference, column)
    index = leaderboard.index { |cs_id, _value| cs_id == college_season.id }
    return nil unless index

    { rank: index + 1, of: leaderboard.size }
  end

  def conference_stat_leaderboard(conference, column)
    @conference_stat_leaderboards ||= {}
    @conference_stat_leaderboards[[ conference, column ]] ||= begin
      direction = STAT_DIRECTIONS.fetch(column)
      entries = college_seasons_by_conference.fetch(conference, []).filter_map do |cs|
        value = stat_per_game_value(cs, column)
        [ cs.id, value ] unless value.nil?
      end
      entries.sort_by { |_cs_id, value| direction == :higher ? -value : value }
    end
  end

  def stat_per_game_value(college_season, column)
    return college_season.yards_per_play if column == :yards_per_play

    total = college_season.public_send(column)
    return nil if total.nil?

    played = games_played_count(college_season)
    return nil if played.zero?

    total.to_f / played
  end

  # Lightweight games-played count for conference-wide leaderboards (every
  # team in the conference, not just ours) — deliberately mirrors the
  # played/not-played definition in game_result above (week 0 excluded,
  # both sides' final_score present) so this never disagrees with the
  # games_played shown elsewhere in the same report.
  def games_played_count(college_season)
    @games_played_counts ||= {}
    @games_played_counts[college_season.id] ||= college_season.games
                                                                .includes(:college_game_stats, :week)
                                                                .count { |g| played_game?(g) }
  end

  def played_game?(game)
    return false if game.week.number.zero?

    stats = game.college_game_stats
    stats.size == 2 && stats.all? { |s| s.final_score.present? }
  end

  def played_game_json(game)
    {
      week_number: game[:week].number,
      home: game[:home],
      opponent: college_json(game[:opponent_college]),
      opponent_ratings: ratings_json(game[:opponent]),
      result: game[:result],
      pregame_projection: pregame_projection(game)
    }
  end

  def remaining_game_json(game)
    {
      week_number: game[:week].number,
      home: game[:home],
      opponent: college_json(game[:opponent_college]),
      opponent_ratings: ratings_json(game[:opponent]),
      projection: pregame_projection(game)
    }
  end
end
