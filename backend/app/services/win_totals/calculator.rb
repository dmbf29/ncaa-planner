module WinTotals
  # Projects a regular-season win total for a college_season using a simple
  # Elo-style model, then turns it into a line for the podcast hosts to argue
  # over/under (see #vegas_win_total: a half-point line, or a whole number
  # when that splits the bets more evenly).
  #
  # Team strength is a weighted average of the team's position-room starter
  # ratings (QB, RB, WR, TE, OL, DL, LB, DB), with the quarterback counting
  # most. The game doesn't expose an actual depth chart/starter flag, so a
  # room's "starters" are its highest-rated players (ROOM_SLOTS), the same
  # stand-in the Roster Breakdown uses. A college with no scraped roster (an
  # FCS opponent, say) falls back to its hand-entered overall, shifted onto the
  # room scale by overall_offset: a hand-entered overall runs a few points
  # lower than the room-based strength of an equally good team (3.6 points in
  # 2026, 5.8 in 2027), so it would otherwise be treated as weaker than it is.
  #
  # The weights and the two curve constants below were chosen by backtesting
  # a full season of results (360 regular-season games): picking winners
  # 69% of the time instead of 64% for the older "average of overall and
  # starters" formula, with better-calibrated odds. The quarterback was by far
  # the strongest single signal; the hand-entered overall added nothing once
  # the rooms were in. The raw fit gave linemen, linebackers and defensive
  # backs no weight at all, which is implausible from one season of data, so
  # every room keeps a base weight and only the QB (and, less so, the DL) is
  # emphasised. Re-run on 2026-2027 (1,170 games with full rosters): the weights
  # held up when fit on one season and scored on the other, so they stay; only
  # the home bonus (0.6 -> 0.2, home teams won 57% in 2026 but 52% in 2027) and
  # the curve scale (9.2 -> 8.7, underdogs were being given too much) moved.
  # Re-run the backtest when more seasons are on record.
  class Calculator
    ROOM_WEIGHTS = {
      "QB" => 0.25, "DL" => 0.15,
      "RB" => 0.10, "WR" => 0.10, "TE" => 0.10, "OL" => 0.10, "LB" => 0.10, "DB" => 0.10
    }.freeze

    # How many of a room's best players count as its starters.
    ROOM_SLOTS = { "QB" => 1, "RB" => 1, "WR" => 3, "TE" => 1, "OL" => 5, "DL" => 4, "LB" => 3, "DB" => 4 }.freeze

    # Canonical (older) position codes in each room; newer screen labels such
    # as REDG or WILL are folded onto these by PositionBoardMapping.canonical.
    ROOM_POSITIONS = {
      "QB" => %w[QB], "RB" => %w[HB FB], "WR" => %w[WR], "TE" => %w[TE],
      "OL" => %w[LT LG C RG RT], "DL" => %w[LE RE DT], "LB" => %w[MLB LOLB ROLB], "DB" => %w[CB FS SS]
    }.freeze

    # Strength bonus awarded to the home team before computing win
    # probability, in the same points as the room ratings.
    HOME_FIELD_BONUS = 0.2

    # Elo-style logistic scale: a strength difference of this many points
    # works out to roughly a 91% win probability for the stronger team.
    RATING_SCALE = 8.7

    # Win-probability bands a single game gets sorted into for the schedule
    # preview: anything decisive enough to call outright vs. a real
    # coin-flip worth debating. Deliberately not symmetric with a wide gap
    # (e.g. 75/25): a coached team's actual conference slate tends to be
    # other similarly-rated teams, so a wide band would leave nearly every
    # game a "coin flip" and defeat the point of calling any of them.
    LIKELY_WIN_THRESHOLD = 0.6
    LIKELY_LOSS_THRESHOLD = 0.4

    # No game is a sure thing: even a big FBS favorite over an FCS team loses
    # now and then, and the backtest's most lopsided games won 93% of the time,
    # not 100%. Capping the odds keeps a "lock" from counting as a guaranteed
    # win in the win total.
    MIN_WIN_PROBABILITY = 0.03
    MAX_WIN_PROBABILITY = 0.97

    # Used when too few teams have both a roster and an overall to measure the
    # real gap (see overall_offset_for).
    DEFAULT_OVERALL_OFFSET = 5.0
    MIN_TEAMS_TO_MEASURE_OFFSET = 10

    # How far a hand-entered overall sits below the room-based strength, measured
    # across the given college_seasons that have both (their student_seasons
    # must be loaded). Falls back to DEFAULT_OVERALL_OFFSET without enough teams.
    def self.overall_offset_for(college_seasons)
      calculator = new
      pairs = college_seasons.filter_map do |college_season|
        strength = calculator.room_strength(college_season)
        [ college_season.overall.to_f, strength ] if strength && college_season.overall
      end
      return DEFAULT_OVERALL_OFFSET if pairs.size < MIN_TEAMS_TO_MEASURE_OFFSET

      (pairs.sum { |_overall, strength| strength } - pairs.sum { |overall, _strength| overall }) / pairs.size
    end

    # `coach_carryover` (a CoachCarryover) says how much each coach's track
    # record is worth on top of their roster. It only shifts game odds
    # (win_probability); team_strength stays roster-only so the form residuals
    # and power rankings are measured against the roster.
    def initialize(overall_offset: DEFAULT_OVERALL_OFFSET, coach_carryover: nil)
      @overall_offset = overall_offset
      @coach_carryover = coach_carryover
    end

    def team_strength(college_season)
      return nil unless college_season

      room_strength(college_season) || (college_season.overall && college_season.overall + @overall_offset)
    end

    # The weighted average of the team's room starter ratings, or nil when it
    # has no rated players at all.
    def room_strength(college_season)
      averages = room_averages(college_season)
      return nil if averages.empty?

      weights = averages.keys.sum { |room| ROOM_WEIGHTS.fetch(room) }
      averages.sum { |room, average| ROOM_WEIGHTS.fetch(room) * average } / weights
    end

    # `home: nil` means a neutral site (no home bonus), e.g. a conference
    # championship game.
    def win_probability(team_college_season, opponent_college_season, home:)
      team = team_strength(team_college_season)
      opponent = team_strength(opponent_college_season)
      return 0.5 if team.nil? || opponent.nil?

      bonus = home.nil? ? 0.0 : (home ? HOME_FIELD_BONUS : -HOME_FIELD_BONUS)
      diff = (team - opponent) + coach_edge(team_college_season, opponent_college_season) + bonus
      (1.0 / (1.0 + (10**(-diff / RATING_SCALE)))).clamp(MIN_WIN_PROBABILITY, MAX_WIN_PROBABILITY)
    end

    # Sorts a single game's win probability into the three buckets the
    # schedule-preview format needs: called outright, or a real debate.
    def game_projection(probability)
      return :likely_win if probability >= LIKELY_WIN_THRESHOLD
      return :likely_loss if probability <= LIKELY_LOSS_THRESHOLD

      :coin_flip
    end

    # `games` is an array of { opponent: college_season_or_nil, home: bool }.
    # Usually a half-point line (e.g. 7.5) so nobody can push, the "hook" real
    # sportsbooks shade to. A win total is lumpy though (the likeliest finish
    # is usually a whole number), so a hook half a win off the middle can turn
    # the line into a 40/60 bet. When the nearest whole number splits over and
    # under more evenly (pushes set aside), the line is that whole number and
    # landing exactly on it is a push, as in a real sportsbook.
    def vegas_win_total(college_season, games)
      return nil if games.empty?

      probabilities = games.map { |g| win_probability(college_season, g[:opponent], home: g[:home]) }
      expected_wins = probabilities.sum
      distribution = win_distribution(probabilities)
      hook = expected_wins.floor + 0.5
      whole = expected_wins.round.to_f
      imbalance(distribution, whole) < imbalance(distribution, hook) ? whole : hook
    end

    # The chance of every possible win total, given each game's win
    # probability (a Poisson-binomial distribution): index i holds P(exactly i
    # wins). Lets the show talk about how likely a team is to clear its line,
    # reach six wins, or finish under.
    def win_distribution(probabilities)
      probabilities.each_with_object([ 1.0 ]) do |probability, distribution|
        distribution.push(0.0)
        (distribution.size - 1).downto(0) do |wins|
          lost = distribution[wins] * (1 - probability)
          won = wins.positive? ? distribution[wins - 1] * probability : 0.0
          distribution[wins] = lost + won
        end
      end
    end

    def room_of(position)
      code = PositionBoardMapping.canonical(position)
      ROOM_POSITIONS.find { |_room, codes| codes.include?(code) }&.first
    end

    private

    # How far a line is from a 50/50 over/under, ignoring pushes.
    def imbalance(distribution, line)
      over = distribution.each_with_index.sum { |chance, wins| wins > line ? chance : 0.0 }
      under = distribution.each_with_index.sum { |chance, wins| wins < line ? chance : 0.0 }
      return Float::INFINITY if (over + under).zero?

      ((over / (over + under)) - 0.5).abs
    end

    # The coaches' track records (and any earlier meetings) in rating points,
    # from the first team's side.
    def coach_edge(college_season, opponent_college_season)
      return 0.0 unless @coach_carryover

      @coach_carryover.matchup_rating_points(college_season&.coach_id, opponent_college_season&.coach_id)
    end

    # { "QB" => 78.0, ... } for every room with at least one rated player.
    def room_averages(college_season)
      by_room = college_season.student_seasons.select(&:overall).group_by { |ss| room_of(ss.position) }
      ROOM_SLOTS.each_with_object({}) do |(room, slots), averages|
        top = Array(by_room[room]).map(&:overall).max(slots)
        averages[room] = top.sum.to_f / top.size unless top.empty?
      end
    end
  end
end
