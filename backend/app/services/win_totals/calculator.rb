module WinTotals
  # Projects a regular-season win total for a college_season using a simple
  # Elo-style model, then shades it to a half-point line so the podcast hosts
  # always have a clean number to argue over/under.
  #
  # Team strength blends two signals:
  # - CollegeSeason#overall, the holistic grade a coach enters by hand.
  # - "starter average": the average overall of the single highest-rated
  #   player at each distinct roster position (QB, HB, WR, LT, CB, etc). The
  #   game doesn't expose an actual depth chart/starter flag, so "highest
  #   overall player listed at that position" is the stand-in for a starter.
  #
  # Both signals are weighted evenly by default (see OVERALL_WEIGHT /
  # STARTER_WEIGHT below) — tune those two constants if one should carry
  # more than the other. A college with no scraped roster (most uncoached
  # opponents) falls back to overall alone.
  class Calculator
    OVERALL_WEIGHT = 0.5
    STARTER_WEIGHT = 0.5

    # Flat strength bonus awarded to the home team before computing win
    # probability. Chosen so that two teams within ~4 overall points of each
    # other flip to favor the home team, per the house rule of thumb.
    HOME_FIELD_BONUS = 4.0

    # Elo-style logistic scale: a strength difference of this many points
    # works out to roughly a 91% win probability for the stronger team.
    RATING_SCALE = 25.0

    STARTER_POSITIONS = (CollegeSeason::OFFENSE_POSITIONS + CollegeSeason::DEFENSE_POSITIONS).freeze

    # Win-probability bands a single game gets sorted into for the schedule
    # preview: anything decisive enough to call outright vs. a real
    # coin-flip worth debating. Deliberately not symmetric with a wide gap
    # (e.g. 75/25) — a coached team's actual conference slate tends to be
    # other similarly-rated teams (a full same-conference schedule rarely
    # produces a >90th-percentile mismatch), so a wide band would leave
    # nearly every game a "coin flip" and defeat the point of calling any of
    # them. 60/40 was chosen by checking the real spread of an in-progress
    # dynasty's schedule and picking the split that gave every team a
    # genuine mix of calls and debates.
    LIKELY_WIN_THRESHOLD = 0.6
    LIKELY_LOSS_THRESHOLD = 0.4

    def team_strength(college_season)
      return nil unless college_season

      overall = college_season.overall
      starter = starter_average_overall(college_season)
      return nil if overall.nil? && starter.nil?
      return starter if overall.nil?
      return overall.to_f if starter.nil?

      (overall * OVERALL_WEIGHT) + (starter * STARTER_WEIGHT)
    end

    def win_probability(team_college_season, opponent_college_season, home:)
      team = team_strength(team_college_season)
      opponent = team_strength(opponent_college_season)
      return 0.5 if team.nil? || opponent.nil?

      diff = (team - opponent) + (home ? HOME_FIELD_BONUS : -HOME_FIELD_BONUS)
      1.0 / (1.0 + (10**(-diff / RATING_SCALE)))
    end

    # Sorts a single game's win probability into the three buckets the
    # schedule-preview format needs: called outright, or a real debate.
    def game_projection(probability)
      return :likely_win if probability >= LIKELY_WIN_THRESHOLD
      return :likely_loss if probability <= LIKELY_LOSS_THRESHOLD

      :coin_flip
    end

    # `games` is an array of { opponent: college_season_or_nil, home: bool }.
    # Always lands on a half-point line (e.g. 7.5, not 7 or 8) by flooring
    # the raw expected-wins total — the same "shade to a hook" trick real
    # sportsbooks use so nobody can push.
    def vegas_win_total(college_season, games)
      return nil if games.empty?

      expected_wins = games.sum { |g| win_probability(college_season, g[:opponent], home: g[:home]) }
      expected_wins.floor + 0.5
    end

    private

    def starter_average_overall(college_season)
      ratings = STARTER_POSITIONS.filter_map do |position|
        college_season.student_seasons.select { |ss| ss.position == position }.filter_map(&:overall).max
      end
      return nil if ratings.empty?

      ratings.sum.to_f / ratings.size
    end
  end
end
