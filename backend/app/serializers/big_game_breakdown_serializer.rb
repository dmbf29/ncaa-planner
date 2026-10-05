# "Big Game Breakdown": the midweek preview episode for the coming week's
# games involving our coached teams. Every game gets a house line (see
# BigGameBreakdown::LineMaker), the stakes and history, a film room (position
# matchups and injuries), a quarterback duel, and one bet per host (see
# BigGameBreakdown::PickLocker). Games are ordered from the most lopsided to
# the closest, so the show builds to the best game.
#
# Requesting a week the first time locks that week's lines and picks; later
# requests return the same ones. Games elsewhere are only mentioned where
# they bear on one of ours (the conference race, the poll neighbors), and
# only from the point in the season where that starts to matter.
class BigGameBreakdownSerializer
  # Standings and poll ripple effects stay out of the show until the races
  # have taken shape.
  MIN_WEEK_FOR_STANDINGS_STAKES = 8

  STANDINGS_TABLE_SIZE = 6
  RIPPLE_GAME_LIMIT = 4
  POLL_NEIGHBOR_RANGE = 3
  RECENT_RESULT_COUNT = 3

  def initialize(season, week_number)
    @season = season
    @week_number = week_number
    @line_maker = BigGameBreakdown::LineMaker.new(season)
    @pick_locker = BigGameBreakdown::PickLocker.new
    @scorecard = BigGameBreakdown::Scorecard.new(season)
    @schedule = PodcastSchedule.new(season)
  end

  def as_json
    week = @season.weeks.find_by(number: @week_number)
    return { focus: { instructions: "No Week #{@week_number} exists for this season." }, games: [] } unless week

    @week = week
    games = ordered_games.map { |entry| game_json(*entry) }

    {
      focus: focus_json(games),
      podcast_date: podcast_date_json,
      season: { id: @season.id, year: @season.year, dynasty: @season.dynasty.name },
      week: { id: week.id, number: week.number, name: week.name },
      poll_week_number: poll_week&.number,
      games: games,
      pick_ledger: pick_ledger_json
    }
  end

  private

  def focus_json(games)
    return { instructions: "None of our coached teams has a game scheduled in Week #{@week_number}." } if games.empty?

    {
      instructions: "Preview this week's #{games.size} game#{'s' if games.size != 1} involving our coached teams. " \
                    "Games are listed from the most lopsided to the closest; the show builds to the last one. " \
                    "Every game closes with each host's single bet."
    }
  end

  def podcast_date_json
    date = @schedule.preview_date(@week_number)
    review_date = @schedule.review_date(@week_number)
    return nil unless date

    { date: date.iso8601, review_date: review_date&.iso8601, week_number: @week_number, position: "before" }
  end

  # ---- data loading --------------------------------------------------------

  def coached_college_seasons
    @coached_college_seasons ||= @season.college_seasons.where.not(coach_id: nil).includes(:college, :coach).to_a
  end

  def coached_college_ids
    @coached_college_ids ||= coached_college_seasons.map(&:college_id).to_set
  end

  def college_seasons_by_college_id
    @college_seasons_by_college_id ||= @season.college_seasons.includes(:college, :coach).index_by(&:college_id)
  end

  def all_games
    @all_games ||= Game.where(week_id: @season.week_ids)
                       .includes(:home_college, :away_college, :college_game_stats, :week)
                       .to_a
  end

  def week_games
    all_games.select { |game| game.week_id == @week.id }
  end

  def our_week_games
    week_games.select { |game| coached_college_ids.include?(game.home_college_id) || coached_college_ids.include?(game.away_college_id) }
  end

  # [[game, lines, picks], ...], most lopsided first (and the closest game
  # last). Lines and picks come from the locked picks once they exist, so a
  # re-run after a roster update still shows what was actually bet.
  def ordered_games
    our_week_games.map do |game|
      lines = @line_maker.call(game, @week.number)
      picks = @pick_locker.call(game, lines)
      lines = locked_lines(lines, picks)
      [ game, lines, picks ]
    end.sort_by { |game, lines, _picks| [ -lines[:spread].abs, game.id ] }
  end

  def locked_lines(lines, picks)
    return lines if picks.empty?

    spread = picks.first.spread_line.to_f
    lines.merge(spread: spread, total: picks.first.total_line.to_f, favorite: spread.negative? ? "home" : "away")
  end

  # ---- per-game ---------------------------------------------------------------

  def game_json(game, lines, picks)
    {
      id: game.id,
      time: game.time&.iso8601,
      conference_game: conference_game?(game),
      both_user_coached: both_coached?(game),
      home: team_json(game.home_college_id),
      away: team_json(game.away_college_id),
      line: line_json(game, lines),
      stakes: stakes_json(game),
      film_room: film_room_json(game),
      quarterback_duel: { home: quarterback_json(game.home_college_id), away: quarterback_json(game.away_college_id) },
      picks: picks.map { |pick| pick_json(pick) }
    }
  end

  def pick_json(pick)
    { host: pick.host, market: pick.market, side: pick.side, bet: pick.description }
  end

  def both_coached?(game)
    coached_college_ids.include?(game.home_college_id) && coached_college_ids.include?(game.away_college_id)
  end

  def conference_game?(game)
    home = conference_of(game.home_college_id)
    home.present? && home == conference_of(game.away_college_id)
  end

  def conference_of(college_id)
    college_seasons_by_college_id[college_id]&.conference
  end

  def line_json(game, lines)
    favorite_home = lines[:favorite] == "home"
    {
      favorite: (favorite_home ? game.home_college : game.away_college).name,
      favorite_is_home: favorite_home,
      underdog: (favorite_home ? game.away_college : game.home_college).name,
      spread: lines[:spread].abs,
      total: lines[:total],
      home_win_probability: lines[:home_win_probability]
    }
  end

  # ---- teams -------------------------------------------------------------------

  def team_json(college_id)
    college_season = college_seasons_by_college_id[college_id]
    results = results_for(college_id)

    {
      college: { id: college_id, name: college_season.college.name, conference: college_season.conference },
      user_coached: coached_college_ids.include?(college_id),
      coach: college_season.coach && { name: college_season.coach.name },
      previous_season: previous_season_json(college_id),
      record: record_json(results),
      conference_record: record_json(results.select { |result| result[:conference_game] }),
      ranking: ranking_for(college_id),
      ratings: { overall: college_season.overall, offense: college_season.offense, defense: college_season.defense },
      streak: streak_json(results),
      recent_results: results.last(RECENT_RESULT_COUNT),
      scoring: scoring_json(results),
      injuries: injuries_json(college_season),
      heisman_candidates: heisman_candidates_for(college_id),
      key_players: key_players_json(college_season)
    }
  end

  # Every regular-season game this team already played, oldest first.
  def results_for(college_id)
    @results_for ||= {}
    @results_for[college_id] ||= all_games.filter_map { |game| result_for(game, college_id) }
                                          .sort_by { |result| result[:week_number] }
  end

  def result_for(game, college_id)
    return nil unless game.week.number.positive? && game.week.number < @week.number
    return nil unless game.home_college_id == college_id || game.away_college_id == college_id

    home = game.home_college_id == college_id
    team_stat = game.college_game_stats.find { |stat| stat.college_id == college_id }
    opponent_id = home ? game.away_college_id : game.home_college_id
    opponent_stat = game.college_game_stats.find { |stat| stat.college_id == opponent_id }
    return nil unless team_stat&.final_score && opponent_stat&.final_score

    {
      week_number: game.week.number,
      opponent: (home ? game.away_college : game.home_college).name,
      home: home,
      team_score: team_stat.final_score,
      opponent_score: opponent_stat.final_score,
      won: team_stat.final_score > opponent_stat.final_score,
      conference_game: conference_game?(game)
    }
  end

  def record_json(results)
    { wins: results.count { |result| result[:won] }, losses: results.count { |result| !result[:won] } }
  end

  # "W3" / "L2": the run of identical results ending at the latest game.
  def streak_json(results)
    return nil if results.empty?

    latest = results.last[:won]
    length = results.reverse.take_while { |result| result[:won] == latest }.size
    { kind: latest ? "W" : "L", length: length }
  end

  def scoring_json(results)
    return nil if results.empty?

    {
      games: results.size,
      points_per_game: (results.sum { |result| result[:team_score] }.to_f / results.size).round(1),
      points_allowed_per_game: (results.sum { |result| result[:opponent_score] }.to_f / results.size).round(1)
    }
  end

  def ranking_for(college_id)
    @rankings ||= poll_week ? poll_week.college_week_rankings.index_by(&:college_id) : {}
    @rankings[college_id]&.ranking
  end

  # The poll entering this week, or the latest earlier one on file when this
  # week's hasn't been entered yet (e.g. only the preseason poll exists
  # before Week 1).
  def poll_week
    return @poll_week if defined?(@poll_week)

    @poll_week = @season.weeks.where("number <= ?", @week.number).order(number: :desc)
                        .find { |week| week.college_week_rankings.exists? }
  end

  # Last season's record and scoring, from the season totals stored on its
  # CollegeSeason (the game log only covers a fraction of other teams'
  # games). nil until the dynasty has a prior season.
  def previous_season_json(college_id)
    previous = previous_college_seasons[college_id]
    return nil unless previous && previous.wins && previous.losses

    games = previous.wins + previous.losses
    {
      year: @season.previous_season.year,
      wins: previous.wins,
      losses: previous.losses,
      conference_wins: previous.conference_wins,
      conference_losses: previous.conference_losses,
      points_per_game: previous.points_for && games.positive? ? (previous.points_for.to_f / games).round(1) : nil,
      points_allowed_per_game: previous.points_against && games.positive? ? (previous.points_against.to_f / games).round(1) : nil
    }
  end

  def previous_college_seasons
    @previous_college_seasons ||= @season.previous_season&.college_seasons&.index_by(&:college_id) || {}
  end

  # ---- stakes -----------------------------------------------------------------

  def stakes_json(game)
    meetings = previous_meetings(game.home_college_id, game.away_college_id)

    {
      conference_game: conference_game?(game),
      conference: conference_game?(game) ? conference_of(game.home_college_id) : nil,
      ranked_matchup: ranking_for(game.home_college_id).present? && ranking_for(game.away_college_id).present?,
      previous_meetings: meetings,
      series: series_json(game, meetings),
      conference_race: standings_stakes? && conference_game?(game) ? conference_race_json(game) : nil,
      elsewhere: standings_stakes? ? elsewhere_json(game) : []
    }
  end

  def standings_stakes?
    @week.number >= MIN_WEEK_FOR_STANDINGS_STAKES
  end

  # Every earlier meeting between the two programs, in this dynasty's
  # seasons, oldest first (empty until the dynasty has history).
  def previous_meetings(college_id_a, college_id_b)
    season_ids = @season.dynasty.seasons.where("year <= ?", @season.year).pluck(:id)
    games = Game.where(week_id: Week.where(season_id: season_ids).select(:id))
                .where("(home_college_id = :a AND away_college_id = :b) OR (home_college_id = :b AND away_college_id = :a)",
                       a: college_id_a, b: college_id_b)
                .includes(:home_college, :away_college, :college_game_stats, week: :season)

    games.filter_map { |game| meeting_json(game) }
         .reject { |meeting| meeting[:year] == @season.year && meeting[:week_number] >= @week.number }
         .sort_by { |meeting| [ meeting[:year], meeting[:week_number] ] }
  end

  def meeting_json(game)
    home_stat = game.college_game_stats.find { |stat| stat.college_id == game.home_college_id }
    away_stat = game.college_game_stats.find { |stat| stat.college_id == game.away_college_id }
    return nil unless home_stat&.final_score && away_stat&.final_score

    {
      year: game.week.season.year,
      week_number: game.week.number,
      home: { name: game.home_college.name, score: home_stat.final_score },
      away: { name: game.away_college.name, score: away_stat.final_score }
    }
  end

  # Wins in the series for each side across `meetings`.
  def series_json(game, meetings)
    return nil if meetings.empty?

    wins = Hash.new(0)
    meetings.each do |meeting|
      winner = meeting[:home][:score] > meeting[:away][:score] ? meeting[:home][:name] : meeting[:away][:name]
      wins[winner] += 1
    end
    { game.home_college.name => wins[game.home_college.name], game.away_college.name => wins[game.away_college.name] }
  end

  # Where the two teams sit in their conference's standings and who's near
  # the top, derived from the games themselves (the stored standings columns
  # lag until a whole gameweek has been committed).
  def conference_race_json(game)
    conference = conference_of(game.home_college_id)
    table = conference_table(conference)
    positions = table.each_with_index.to_h { |row, index| [ row[:college_id], index + 1 ] }
    shown = table.first(STANDINGS_TABLE_SIZE).map { |row| row.except(:college_id) }

    {
      conference: conference,
      home_position: positions[game.home_college_id],
      away_position: positions[game.away_college_id],
      table: shown
    }
  end

  # Teams in a conference, best conference record first (ties by overall
  # record), counting only games already played.
  def conference_table(conference)
    @conference_tables ||= {}
    @conference_tables[conference] ||= begin
      rows = college_seasons_by_college_id.values.select { |cs| cs.conference == conference }.map do |cs|
        results = results_for(cs.college_id)
        conf = record_json(results.select { |result| result[:conference_game] })
        overall = record_json(results)
        { college_id: cs.college_id, name: cs.college.name, user_coached: coached_college_ids.include?(cs.college_id),
          conference_record: conf, overall_record: overall, plays_this_week: week_games.any? { |g| [ g.home_college_id, g.away_college_id ].include?(cs.college_id) } }
      end
      rows.sort_by { |row| [ -row[:conference_record][:wins], row[:conference_record][:losses], -row[:overall_record][:wins], row[:name] ] }
    end
  end

  # Other games this week that bear on this one: a conference game among the
  # teams at the top of one of our teams' standings, or a ranked game next to
  # one of our teams in the poll. Brief, so the hosts can name-check them.
  def elsewhere_json(game)
    ours = [ game.home_college_id, game.away_college_id ]
    others = week_games.reject { |other| other.id == game.id }
    entries = []

    others.each do |other|
      reason = ripple_reason(game, other, ours)
      next unless reason

      entries << { home: other.home_college.name, away: other.away_college.name, reason: reason }
    end

    entries.first(RIPPLE_GAME_LIMIT)
  end

  def ripple_reason(game, other, ours)
    if conference_game?(game) && conference_game?(other) && conference_of(other.home_college_id) == conference_of(game.home_college_id)
      top = conference_table(conference_of(game.home_college_id)).first(4).map { |row| row[:college_id] }
      return "conference title race" if ([ other.home_college_id, other.away_college_id ] & top).any?
    end

    our_ranks = ours.filter_map { |id| ranking_for(id) }
    other_ranks = [ other.home_college_id, other.away_college_id ].filter_map { |id| ranking_for(id) }
    if other_ranks.size == 2 && our_ranks.any? { |rank| other_ranks.any? { |r| (r - rank).abs <= POLL_NEIGHBOR_RANGE } }
      return "ranked teams right next to ours in the poll"
    end

    nil
  end

  # ---- film room ----------------------------------------------------------------

  def film_room_json(game)
    home = college_seasons_by_college_id[game.home_college_id]
    away = college_seasons_by_college_id[game.away_college_id]
    home_groups = home.position_group_averages
    away_groups = away.position_group_averages

    { matchups: position_matchups(home, away, home_groups, away_groups) + position_matchups(away, home, away_groups, home_groups) }
      .tap { |room| room[:matchups] = room[:matchups].compact.sort_by { |matchup| -matchup[:edge].abs } }
  end

  # How one team's offense lines up against the other's defense, three ways.
  def position_matchups(attack_cs, defend_cs, attack_groups, defend_groups)
    passing = average_of(attack_groups["Quarterbacks"], attack_groups["Wide Receivers"])
    [
      matchup_json("passing game vs. the secondary", attack_cs, defend_cs, passing, defend_groups["Secondary"]),
      matchup_json("offensive line vs. the defensive line", attack_cs, defend_cs, attack_groups["Offensive Line"], defend_groups["Defensive Line"]),
      matchup_json("running backs vs. the linebackers", attack_cs, defend_cs, attack_groups["Running Backs"], defend_groups["Linebackers"])
    ]
  end

  def matchup_json(label, attack_cs, defend_cs, attack_rating, defend_rating)
    return nil if attack_rating.nil? || defend_rating.nil?

    {
      label: label,
      offense: attack_cs.college.name,
      offense_rating: attack_rating,
      defense: defend_cs.college.name,
      defense_rating: defend_rating,
      edge: attack_rating - defend_rating
    }
  end

  def average_of(*values)
    present = values.compact
    present.empty? ? nil : (present.sum.to_f / present.size).round
  end

  # The quarterback is left out: he gets his own segment (see
  # quarterback_json), so the rest of the offense is who's worth watching.
  def key_players_json(college_season)
    non_quarterbacks = college_season.best_offensive_players(limit: 4).reject { |player| player.position == "QB" }
    {
      offense: non_quarterbacks.first(3).map { |player| player_json(player) },
      defense: college_season.best_defensive_players(limit: 2).map { |player| player_json(player) }
    }
  end

  def player_json(student_season)
    {
      name: student_season.student.name,
      position: student_season.position,
      overall: student_season.overall,
      dev_trait: student_season.dev_trait,
      class_year: student_season.class_year,
      season_stats: season_stats_for(student_season)
    }
  end

  # Season-to-date production through the week before this game, held back
  # for the first few weeks when it's too small a sample to talk about.
  def season_stats_for(student_season)
    return nil if @week.number < SeasonWeeksSerializer::MIN_WEEK_NUMBER_FOR_SEASON_STATS

    PlayerSeasonStats.call(student_season, through_week_number: @week.number - 1)
  end

  # Players from this team on the Heisman watch list for this game, with the
  # usual player detail (production included), whoever's side they're on.
  def heisman_candidates_for(college_id)
    @heisman_candidates ||= heisman_week ? heisman_week.heisman_candidates.includes(student_season: [ :student, { college_season: :college } ]).to_a : []
    @heisman_candidates.select { |candidate| candidate.student_season.college_season.college_id == college_id }
                       .map { |candidate| player_json(candidate.student_season) }
  end

  # The watch list entering this week, or the latest earlier one on file.
  def heisman_week
    return @heisman_week if defined?(@heisman_week)

    @heisman_week = @season.weeks.where("number <= ?", @week.number).order(number: :desc)
                           .find { |week| week.heisman_candidates.exists? }
  end

  # The team's top-rated QB, the same stand-in for "the starter" the rest of
  # the app uses.
  def quarterback_json(college_id)
    college_season = college_seasons_by_college_id[college_id]
    qb = college_season.student_seasons.includes(:student).where(position: "QB").order(overall: :desc).first
    qb && player_json(qb)
  end

  # Players hurt as of the previous week's games: the injury that matters for
  # this game is either "out for it" or "back for it".
  def injuries_json(college_season)
    previous_week = @season.weeks.find_by(number: @week.number - 1)
    return [] unless previous_week

    roster = college_season.student_seasons.includes(:student, injuries: { game: :week }).to_a
    roster.flat_map(&:injuries).select { |injury| injury.active_as_of?(previous_week) }.map do |injury|
      injury_json(injury, roster)
    end
  end

  def injury_json(injury, roster)
    student_season = injury.student_season
    depth = roster.select { |player| player.position == student_season.position && player.overall.present? }
                  .sort_by { |player| -player.overall }
    replacement = depth.find { |player| player.id != student_season.id }

    {
      name: student_season.student.name,
      position: student_season.position,
      overall: student_season.overall,
      starter: depth.first&.id == student_season.id,
      description: injury.description,
      status: injury_status(injury),
      replacement: replacement && { name: replacement.student.name, overall: replacement.overall }
    }
  end

  # out_for_season, out_this_game, or returning_this_game.
  def injury_status(injury)
    return "out_for_season" if injury.out_for_season?

    injury.return_week_number > @week.number ? "out_this_game" : "returning_this_game"
  end

  # ---- pick ledger -------------------------------------------------------------

  # The hosts' record entering this week plus how last week's bets went, so
  # the show can open on where the scoreboard stands.
  def pick_ledger_json
    {
      season_record: @scorecard.record(through_week_number: @week.number - 1),
      last_week: @scorecard.week_results(@week.number - 1)
    }
  end
end
