module BigGameBreakdown
  # The house spread and total for a game, built on the same team strength the
  # Win Totals show uses (WinTotals::Calculator) so the two shows agree on who
  # is good.
  #
  # Spread: a backtest of 1,170 regular-season games (2026-2027) found each
  # point of strength gap was worth about 2.4 points of final margin, with
  # about a third of a point of home-field advantage on top. Margins are noisy
  # (a standard deviation near 18 points), so a spread bet is close to a coin
  # flip, which is the point.
  #
  # Form: the roster rating can't know a team has been losing (or winning)
  # more than its roster says, so `call` also adjusts the spread for results.
  # For each game already played, a team's residual is its actual margin minus
  # what its roster strength predicted (with home field), so a loss to a
  # strong team doesn't count against it the way a loss to a weak one does.
  # A team's average residual is shrunk toward zero by FORM_PRIOR_GAMES (a
  # backtest of last season's games put the best weight at roughly 10 games'
  # worth of belief in the roster; it cut the typical miss from 15.1 to 14.8
  # points, and from 14.8 to 14.2 once both teams had 3+ games), and the
  # spread moves by the home team's adjustment minus the away team's.
  # `spread_for` deliberately does NOT do this: the Win Totals show uses it
  # for preseason lines, before any results exist, so it stays roster-only
  # unless asked to add coaches' track records.
  #
  # Coach carryover: a user coach's results from earlier seasons (see
  # WinTotals::CoachCarryover) count like games already played, so a coach who
  # beat their roster by 15 a game last year starts this one with the spread
  # already leaning their way instead of from zero. CPU teams have no history.
  # Between two user coaches the carryover is halved and their own earlier
  # meetings are added (see WinTotals::CoachCarryover).
  #
  # Total: both teams' scoring and points-allowed averages through the weeks
  # already played, blended toward the league average total while the sample
  # is small (the early weeks, before there's anything to average). Totals
  # from a team's stats are unadjusted for opponent, which is fine for a show.
  #
  # Both lines are shaded to a half-point so a bet never pushes.
  class LineMaker
    # Past any real week number: every game played so far.
    ALL_WEEKS = 1000

    POINTS_PER_RATING_POINT = 2.4
    HOME_FIELD_POINTS = 0.4

    # League average total points across the 403-game backtest; used until
    # the season has results of its own.
    DEFAULT_TOTAL = 55.0

    # Games of scoring history (per team) at which a team's own numbers are
    # trusted completely over the league average.
    FULL_SAMPLE_GAMES = 6

    # Last season's scoring stands in for up to this many games of this
    # season's (fewer as real games come in), so Week 1 isn't just the league
    # average. Rosters turn over, so it's deliberately a light prior.
    PRIOR_GAMES = 3

    # Games' worth of belief in the roster rating when blending in results:
    # a team's results get weight n / (n + FORM_PRIOR_GAMES).
    FORM_PRIOR_GAMES = 10

    def initialize(season, calculator: WinTotals::Calculator.new, coach_carryover: nil)
      @season = season
      @calculator = calculator
      @coach_carryover = coach_carryover || WinTotals::CoachCarryover.new(season)
    end

    # `week_number` is the week being previewed; only weeks before it feed the
    # scoring averages. Returns:
    #   spread:       home-side line (-6.5 = home favored by 6.5), roster
    #                 strength adjusted for results so far
    #   favorite:     "home" or "away"
    #   total:        projected points
    #   total_edge:   unrounded projected total minus the league average
    #   home_win_probability
    #   form:         { home:, away:, head_to_head: } each team { games:,
    #                 average:, carryover: }
    #                 (average points per game above/below what the roster
    #                 predicted, nil before the team has played; carryover is
    #                 the same for the coach's earlier seasons, nil for a team
    #                 without a coach record), and
    #                 head_to_head: { games:, average: } from the home coach's
    #                 side when two user coaches have met before, else nil;
    #                 adjustment: the points the spread moved for results
    #   rated:        false when either team has nothing to rate (no roster),
    #                 in which case the line is a placeholder, not a real line
    def call(game, week_number)
      home_cs = college_season(game.home_college_id)
      away_cs = college_season(game.away_college_id)
      home_form = form(game.home_college_id, week_number)
      away_form = form(game.away_college_id, week_number)
      home_coach_id = home_cs&.coach_id
      away_coach_id = away_cs&.coach_id
      scale = home_coach_id && away_coach_id ? WinTotals::CoachCarryover::USER_VS_USER_WEIGHT : 1.0
      head_to_head = home_coach_id && away_coach_id ? @coach_carryover.head_to_head(home_coach_id, away_coach_id) : []
      adjustment = weighted_form(game.home_college_id, week_number, scale) - weighted_form(game.away_college_id, week_number, scale)
      adjustment += @coach_carryover.head_to_head_points(home_coach_id, away_coach_id) if head_to_head.any?
      margin = expected_home_margin(home_cs, away_cs) + adjustment

      {
        spread: line_for(margin),
        favorite: margin >= 0 ? "home" : "away",
        total: nearest_half(projected_total(game, week_number)),
        total_edge: (projected_total(game, week_number) - league_average_total(week_number)).round(1),
        home_win_probability: shifted_probability(@calculator.win_probability(home_cs, away_cs, home: true), adjustment).round(2),
        form: { home: home_form, away: away_form, adjustment: adjustment.round(1), head_to_head: head_to_head_json(head_to_head) },
        rated: !@calculator.team_strength(home_cs).nil? && !@calculator.team_strength(away_cs).nil?
      }
    end

    # Just the home-side spread for two teams (-6.5 = home favored by 6.5), from
    # roster strength alone, for other shows that want the same line without
    # the totals work or any in-season results (Win Totals, which is preseason).
    # `with_coaches` adds each coach's track record from earlier seasons.
    def spread_for(home_cs, away_cs, with_coaches: false)
      margin = expected_home_margin(home_cs, away_cs)
      margin += @coach_carryover.matchup_margin(home_cs&.coach_id, away_cs&.coach_id) if with_coaches
      line_for(margin)
    end

    # Residuals from each side of every game between two user coaches this
    # season has played: { [coach_id, rival_id] => [residual, ...] }, the
    # residual measured from the first coach's side.
    def head_to_head_residuals(week_number = ALL_WEEKS)
      completed_games(week_number).each_with_object({}) do |game, memo|
        home_cs = college_season(game[:home_id])
        away_cs = college_season(game[:away_id])
        next unless home_cs&.coach_id && away_cs&.coach_id && @calculator.team_strength(home_cs) && @calculator.team_strength(away_cs)

        residual = (game[:home_score] - game[:away_score]) - expected_home_margin(home_cs, away_cs)
        (memo[[ home_cs.coach_id, away_cs.coach_id ]] ||= []) << residual
        (memo[[ away_cs.coach_id, home_cs.coach_id ]] ||= []) << -residual
      end
    end

    # Every residual (actual margin minus roster-predicted margin, from the
    # coach's side) by coach for the games this season has played, for
    # WinTotals::CoachCarryover to carry into later seasons.
    def residuals_by_coach(week_number = ALL_WEEKS)
      residuals_by_college(week_number).each_with_object({}) do |(college_id, values), memo|
        coach_id = college_season(college_id)&.coach_id
        (memo[coach_id] ||= []).concat(values) if coach_id && values.any?
      end
    end

    private

    def college_season(college_id)
      college_seasons_by_college_id[college_id]
    end

    # Loaded once (rosters included): `call` rates both teams and every past
    # opponent for the form residuals.
    def college_seasons_by_college_id
      @college_seasons_by_college_id ||= @season.college_seasons.includes(student_seasons: :student).index_by(&:college_id)
    end

    def expected_home_margin(home_cs, away_cs)
      home = @calculator.team_strength(home_cs)
      away = @calculator.team_strength(away_cs)
      return HOME_FIELD_POINTS if home.nil? || away.nil?

      ((home - away) * POINTS_PER_RATING_POINT) + HOME_FIELD_POINTS
    end

    # The home-side line for an expected home margin: negative when the home
    # team is the favorite.
    def line_for(margin)
      half = nearest_half(margin.abs)
      margin >= 0 ? -half : half
    end

    # { games:, average:, carryover: } for a team: its mean residual (actual
    # margin minus roster-predicted margin, from its own side) over the games
    # already played, and the same for its coach's earlier seasons (nil when
    # the team has no coach record).
    def form(college_id, week_number)
      residuals = residuals_by_college(week_number)[college_id] || []
      carried = carried_residuals(college_id)
      { games: residuals.size, average: average_of(residuals), carryover: carried.empty? ? nil : { games: carried.size, average: average_of(carried) } }
    end

    def average_of(residuals)
      residuals.empty? ? nil : (residuals.sum / residuals.size).round(1)
    end

    # This season's results plus the coach's earlier ones, shrunk by how many
    # games back them up: sum / (n + FORM_PRIOR_GAMES). `carried_scale` damps
    # only the earlier seasons' share.
    def weighted_form(college_id, week_number, carried_scale = 1.0)
      current = residuals_by_college(week_number)[college_id] || []
      carried = carried_residuals(college_id)
      (current.sum(0.0) + (carried_scale * carried.sum(0.0))) / (current.size + carried.size + FORM_PRIOR_GAMES)
    end

    def carried_residuals(college_id)
      coach_id = college_season(college_id)&.coach_id
      coach_id ? @coach_carryover.residuals(coach_id) : []
    end

    def head_to_head_json(residuals)
      residuals.empty? ? nil : { games: residuals.size, average: average_of(residuals) }
    end

    # Nudges a roster-only home win probability by `adjustment` points of
    # margin, on the same logistic scale the Win Totals show uses.
    def shifted_probability(probability, adjustment)
      return probability if adjustment.zero?

      scale = WinTotals::Calculator::RATING_SCALE
      rating_gap = scale * Math.log10(probability / (1.0 - probability))
      shifted = rating_gap + (adjustment / POINTS_PER_RATING_POINT)
      1.0 / (1.0 + (10**(-shifted / scale)))
    end

    # { college_id => [residual, ...] } over every game played before
    # `week_number`: how far each team's actual margin landed from what the
    # roster ratings predicted for that game.
    def residuals_by_college(week_number)
      @residuals_by_college ||= {}
      @residuals_by_college[week_number] ||= completed_games(week_number).each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |game, memo|
        home_cs = college_season(game[:home_id])
        away_cs = college_season(game[:away_id])
        next unless home_cs && away_cs && @calculator.team_strength(home_cs) && @calculator.team_strength(away_cs)

        residual = (game[:home_score] - game[:away_score]) - expected_home_margin(home_cs, away_cs)
        memo[game[:home_id]] << residual
        memo[game[:away_id]] << -residual
      end
    end

    # The nearest value ending in .5 (never a whole number, so no pushes).
    def nearest_half(value)
      (value - 0.5).round + 0.5
    end

    def projected_total(game, week_number)
      @projected_totals ||= {}
      @projected_totals[game.id] ||= begin
        baseline = league_average_total(week_number)
        home = scoring(game.home_college_id, week_number)
        away = scoring(game.away_college_id, week_number)
        sample = [ home[:games], away[:games] ].min
        if sample.zero?
          baseline
        else
          from_stats = ((home[:scored] + away[:allowed]) / 2.0) + ((away[:scored] + home[:allowed]) / 2.0)
          weight = [ sample.to_f / FULL_SAMPLE_GAMES, 1.0 ].min
          baseline + (weight * (from_stats - baseline))
        end
      end
    end

    # { games:, scored:, allowed: } per game over the weeks played
    # before `week_number`, topped up with last season's per-game numbers
    # (worth PRIOR_GAMES games, less as the season fills in). `games` is the
    # effective sample size.
    def scoring(college_id, week_number)
      results = results_by_college(week_number)[college_id] || []
      prior = previous_scoring(college_id)
      prior_games = prior ? [ PRIOR_GAMES - results.size, 0 ].max : 0
      games = results.size + prior_games
      return { games: 0, scored: 0.0, allowed: 0.0 } if games.zero?

      scored = results.sum { |points, _allowed| points } + (prior_games * (prior&.fetch(:scored) || 0))
      allowed = results.sum { |_points, conceded| conceded } + (prior_games * (prior&.fetch(:allowed) || 0))
      { games: games, scored: scored.to_f / games, allowed: allowed.to_f / games }
    end

    # Last season's points scored and allowed per game, from the totals on its
    # CollegeSeason; nil when there's no prior season or no numbers.
    def previous_scoring(college_id)
      previous = previous_college_seasons[college_id]
      return nil unless previous&.points_for && previous.points_against && previous.wins && previous.losses

      games = previous.wins + previous.losses
      return nil unless games.positive?

      { scored: previous.points_for.to_f / games, allowed: previous.points_against.to_f / games }
    end

    def previous_college_seasons
      @previous_college_seasons ||= @season.previous_season&.college_seasons&.index_by(&:college_id) || {}
    end

    # Average total in this season's games so far; before any are played, last
    # season's league-wide average (two teams' worth of scoring per game), then
    # the backtest default.
    def league_average_total(week_number)
      games = completed_games(week_number)
      return previous_league_average_total || DEFAULT_TOTAL if games.empty?

      games.sum { |game| game[:home_score] + game[:away_score] }.to_f / games.size
    end

    def previous_league_average_total
      return @previous_league_average_total if defined?(@previous_league_average_total)

      scored = 0
      games = 0
      previous_college_seasons.each_value do |previous|
        next unless previous.points_for && previous.wins && previous.losses

        scored += previous.points_for
        games += previous.wins + previous.losses
      end
      @previous_league_average_total = games.positive? ? 2.0 * scored / games : nil
    end

    def results_by_college(week_number)
      @results_by_college ||= {}
      @results_by_college[week_number] ||= completed_games(week_number).each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |game, memo|
        memo[game[:home_id]] << [ game[:home_score], game[:away_score] ]
        memo[game[:away_id]] << [ game[:away_score], game[:home_score] ]
      end
    end

    # Every game already played before `week_number` (Week 0 included), as
    # { home_id:, away_id:, home_score:, away_score: }. Games missing a final
    # score for either side are skipped.
    def completed_games(week_number)
      @completed_games ||= {}
      @completed_games[week_number] ||= begin
        rows = CollegeGameStat.joins(game: :week)
                              .where(weeks: { season_id: @season.id })
                              .where("weeks.number < ?", week_number)
                              .where.not(final_score: nil)
                              .pluck(:game_id, :college_id, :final_score, "games.home_college_id", "games.away_college_id")
        rows.group_by(&:first).values.select { |stats| stats.size == 2 }.map do |stats|
          scores = stats.to_h { |_game_id, college_id, score, _home_id, _away_id| [ college_id, score ] }
          home_id, away_id = stats.first.values_at(3, 4)
          { home_id: home_id, away_id: away_id, home_score: scores[home_id], away_score: scores[away_id] }
        end
      end
    end
  end
end
