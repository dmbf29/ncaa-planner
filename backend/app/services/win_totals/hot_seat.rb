module WinTotals
  # The "hot seat thermometer" for one coach: how safe is his job if his team
  # hits its win total, and how fast does that change if it doesn't. It pairs
  # the coach's current job security (a 0-100 percentage entered from the game)
  # with the Vegas line and the win distribution built from the schedule.
  #
  # This is an editorial model, not the game's actual firing logic (which we
  # can't see): every win above or below the number moves job security by
  # WIN_SWING points, and a coach whose security lands under OUT_BELOW is out.
  # "Hitting the number" means finishing with the fewest wins that clear the
  # line (7 wins on a 6.5 line) and leaves security where it is. The
  # thresholds mirror the labels the game shows (see Coach#job_security_label),
  # plus a final "Out" band below the game's lowest one.
  #
  # The early test asks the same question for a bad start: a loss in the
  # opening stretch (up to the first bye week) costs EARLY_LOSS_PENALTY, so a
  # coach on thin ice can be shown the door at the bye. It is only reported
  # when the coach could actually be fired inside that stretch.
  class HotSeat
    WIN_SWING = 10
    OUT_BELOW = 35
    EARLY_LOSS_PENALTY = 15
    MAX_EARLY_GAMES = 5
    LADDER_BELOW = 3
    LADDER_ABOVE = 2

    # Lowest security first, as [floor, game label, thermometer reading].
    BANDS = [
      [ 80, "Safe", "ICE COLD" ],
      [ 65, "Safe for Now", "COOL" ],
      [ 50, "Low", "WARM" ],
      [ OUT_BELOW, "Hot Seat", "HOT" ],
      [ -Float::INFINITY, "Out", "ON FIRE" ]
    ].freeze

    # coach: needs #name, #job_security, #nil_amount
    # games: [{ week_number:, home:, opponent:, projection:, win_probability:, point_spread: }] in week order
    # bye_week_number: the team's first bye after the preseason week, or nil
    def initialize(coach:, line:, games:, distribution:, calculator:, bye_week_number: nil)
      @coach = coach
      @line = line
      @games = games
      @distribution = distribution
      @calculator = calculator
      @bye_week_number = bye_week_number
    end

    def call
      return nil if @coach.job_security.nil? || @line.nil? || @games.empty?

      {
        coach: coach_json,
        number: { line: @line, wins_to_hit: wins_to_hit },
        at_the_number: outcome(wins_to_hit),
        one_win_under: wins_to_hit.positive? ? outcome(wins_to_hit - 1) : nil,
        wins_needed_to_keep_job: wins_needed_to_keep_job,
        chance_of_finishing_under: probability_below(wins_to_hit),
        ladder: ladder,
        early_test: early_test
      }
    end

    private

    def security
      @coach.job_security
    end

    def wins_to_hit
      @line.ceil
    end

    def coach_json
      {
        name: @coach.name,
        job_security: security,
        label: band_for(security)[1],
        reading: band_for(security)[2],
        buyout_dollars: @coach.nil_amount && @coach.nil_amount * TeamBreakdownSerializer::DOLLARS_PER_NIL_POINT
      }
    end

    # Job security after finishing the season with this many wins.
    def security_after(wins)
      (security + (WIN_SWING * (wins - wins_to_hit))).clamp(0, 100)
    end

    def outcome(wins)
      value = security_after(wins)
      band = band_for(value)
      {
        wins: wins,
        losses: @games.size - wins,
        job_security: value,
        label: band[1],
        reading: band[2],
        out: band[1] == "Out",
        probability: @distribution[wins] || 0.0
      }
    end

    def ladder
      low = [ wins_to_hit - LADDER_BELOW, 0 ].max
      high = [ wins_to_hit + LADDER_ABOVE, @games.size ].min
      (low..high).map { |wins| outcome(wins) }
    end

    # The fewest wins that still leave him above the Out line.
    def wins_needed_to_keep_job
      [ wins_to_hit + ((OUT_BELOW - security) / WIN_SWING.to_f).ceil, 0 ].max
    end

    def probability_below(wins)
      @distribution.first([ wins, @distribution.size ].min).sum
    end

    def band_for(value)
      BANDS.find { |floor, _label, _reading| value >= floor }
    end

    # ---- early test ------------------------------------------------------

    def early_window
      @early_window ||= begin
        before_bye = @bye_week_number ? @games.select { |g| g[:week_number] < @bye_week_number } : @games
        before_bye.first(MAX_EARLY_GAMES)
      end
    end

    # How many early losses he can absorb before security drops under the Out
    # line: -1 means he's already under it.
    def allowed_early_losses
      ((security - OUT_BELOW) / EARLY_LOSS_PENALTY.to_f).floor
    end

    def early_test
      return nil if early_window.empty? || allowed_early_losses >= early_window.size

      window_distribution = @calculator.win_distribution(early_window.map { |g| g[:win_probability] })
      wins_needed = early_window.size - [ allowed_early_losses, 0 ].max
      {
        games: early_window.map { |g| g.slice(:week_number, :home, :opponent, :projection, :win_probability, :point_spread) },
        decision_point: decision_point,
        allowed_losses: [ allowed_early_losses, 0 ].max,
        wins_needed: wins_needed,
        easy_start: early_window.all? { |g| g[:projection] == :likely_win },
        chance_of_exit: window_distribution.first(wins_needed).sum
      }
    end

    def decision_point
      last_week = early_window.last[:week_number]
      if @bye_week_number && early_window.size == @games.count { |g| g[:week_number] < @bye_week_number }
        { kind: "bye", week: @bye_week_number }
      else
        { kind: "after_week", week: last_week }
      end
    end
  end
end
