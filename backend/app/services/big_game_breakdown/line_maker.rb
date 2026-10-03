module BigGameBreakdown
  # The house spread and total for a game, built on the same team strength the
  # Win Totals show uses (WinTotals::Calculator) so the two shows agree on who
  # is good.
  #
  # Spread: a backtest of 403 regular-season games found each point of strength
  # gap was worth about 2.1 points of final margin, with about a point of
  # home-field advantage on top. Margins are noisy (a standard deviation near
  # 18 points), so a spread bet is close to a coin flip, which is the point.
  #
  # Total: both teams' scoring and points-allowed averages through the weeks
  # already played, blended toward the league average total while the sample
  # is small (the early weeks, before there's anything to average). Totals
  # from a team's stats are unadjusted for opponent, which is fine for a show.
  #
  # Both lines are shaded to a half-point so a bet never pushes.
  class LineMaker
    POINTS_PER_RATING_POINT = 2.1
    HOME_FIELD_POINTS = 1.0

    # League average total points across the 403-game backtest; used until
    # the season has results of its own.
    DEFAULT_TOTAL = 55.0

    # Games of scoring history (per team) at which a team's own numbers are
    # trusted completely over the league average.
    FULL_SAMPLE_GAMES = 6

    def initialize(season, calculator: WinTotals::Calculator.new)
      @season = season
      @calculator = calculator
    end

    # `week_number` is the week being previewed; only weeks before it feed the
    # scoring averages. Returns:
    #   spread:       home-side line (-6.5 = home favored by 6.5)
    #   favorite:     "home" or "away"
    #   total:        projected points
    #   total_edge:   unrounded projected total minus the league average
    #   home_win_probability
    def call(game, week_number)
      home_cs = college_season(game.home_college_id)
      away_cs = college_season(game.away_college_id)

      {
        spread: home_line(home_cs, away_cs),
        favorite: favorite(home_cs, away_cs),
        total: nearest_half(projected_total(game, week_number)),
        total_edge: (projected_total(game, week_number) - league_average_total(week_number)).round(1),
        home_win_probability: @calculator.win_probability(home_cs, away_cs, home: true).round(2)
      }
    end

    private

    def college_season(college_id)
      @college_seasons ||= {}
      @college_seasons[college_id] ||= @season.college_seasons.includes(student_seasons: :student).find_by(college_id: college_id)
    end

    def expected_home_margin(home_cs, away_cs)
      home = @calculator.team_strength(home_cs)
      away = @calculator.team_strength(away_cs)
      return HOME_FIELD_POINTS if home.nil? || away.nil?

      ((home - away) * POINTS_PER_RATING_POINT) + HOME_FIELD_POINTS
    end

    def favorite(home_cs, away_cs)
      expected_home_margin(home_cs, away_cs) >= 0 ? "home" : "away"
    end

    def home_line(home_cs, away_cs)
      margin = nearest_half(expected_home_margin(home_cs, away_cs).abs)
      favorite(home_cs, away_cs) == "home" ? -margin : margin
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

    # { games:, scored:, allowed: } per game, over the regular-season weeks
    # before `week_number`.
    def scoring(college_id, week_number)
      results = results_by_college(week_number)[college_id] || []
      return { games: 0, scored: 0.0, allowed: 0.0 } if results.empty?

      {
        games: results.size,
        scored: results.sum { |scored, _allowed| scored }.to_f / results.size,
        allowed: results.sum { |_scored, allowed| allowed }.to_f / results.size
      }
    end

    def league_average_total(week_number)
      games = completed_games(week_number)
      return DEFAULT_TOTAL if games.empty?

      games.sum { |(_a, a_score), (_b, b_score)| a_score + b_score }.to_f / games.size
    end

    def results_by_college(week_number)
      @results_by_college ||= {}
      @results_by_college[week_number] ||= completed_games(week_number).each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |((a_id, a_score), (b_id, b_score)), memo|
        memo[a_id] << [ a_score, b_score ]
        memo[b_id] << [ b_score, a_score ]
      end
    end

    # Every regular-season game already played before `week_number`, each as
    # [[college_id, score], [college_id, score]]. Games missing a final score
    # for either side are skipped.
    def completed_games(week_number)
      @completed_games ||= {}
      @completed_games[week_number] ||= begin
        rows = CollegeGameStat.joins(game: :week)
                              .where(weeks: { season_id: @season.id })
                              .where("weeks.number > 0 AND weeks.number < ?", week_number)
                              .where.not(final_score: nil)
                              .pluck(:game_id, :college_id, :final_score)
        rows.group_by(&:first).values.select { |stats| stats.size == 2 }
            .map { |stats| stats.map { |_game_id, college_id, score| [ college_id, score ] } }
      end
    end
  end
end
