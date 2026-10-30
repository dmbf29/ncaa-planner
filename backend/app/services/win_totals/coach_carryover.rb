module WinTotals
  # How each coach's teams have played against their rosters in the dynasty's
  # earlier seasons, so a user coach's habits carry into the next one. A
  # backtest of 2026-2027 found user-controlled teams match their rosters on
  # average but individual coaches miss by a lot (UL Monroe beat its roster by
  # about 17 points a game both years, Georgia Southern missed by about 10) and
  # the miss repeats from one season to the next. CPU teams have no coach
  # record, so this only ever moves coached teams.
  #
  # The residual is the same one BigGameBreakdown::LineMaker uses for in-season
  # form (actual margin minus roster-predicted margin, from the coach's side),
  # and it follows the coach, not the school: a coach who moves programs brings
  # their record along. Carried games are weighted like games already played
  # (see LineMaker::FORM_PRIOR_GAMES), so one season's worth is trusted about
  # half and two seasons about two-thirds.
  #
  # Two coaches facing each other is different: a coach's edge looked much
  # smaller against another user than against the CPU (UL Monroe +20 vs. CPU
  # but about +9 vs. users; Georgia Southern -14 vs. CPU but about +3 vs.
  # users), so the carryover counts for USER_VS_USER_WEIGHT of its size, and
  # the two coaches' own earlier meetings are added on top, shrunk hard
  # (HEAD_TO_HEAD_PRIOR_GAMES) since a pair has only ever met once a season.
  # A leave-one-season-out check on the 12 games between users cut the typical
  # miss from 15.3 to 13.8 points; it is too few games to be more than a hint,
  # so re-check it as seasons are added.
  class CoachCarryover
    USER_VS_USER_WEIGHT = 0.5
    HEAD_TO_HEAD_PRIOR_GAMES = 3

    def initialize(season)
      @season = season
    end

    # Every residual (points above or below the roster prediction) a coach
    # earned in earlier seasons; empty for a coach with no history.
    def residuals(coach_id)
      residuals_by_coach.fetch(coach_id, [])
    end

    # { games:, average: } for display; average is nil without history.
    def record(coach_id)
      values = residuals(coach_id)
      { games: values.size, average: values.empty? ? nil : (values.sum / values.size).round(1) }
    end

    # The points a coach's history moves a game's margin, shrunk toward zero.
    def margin_points(coach_id)
      values = residuals(coach_id)
      return 0.0 if values.empty?

      values.sum(0.0) / (values.size + BigGameBreakdown::LineMaker::FORM_PRIOR_GAMES)
    end

    # How a coach did in earlier meetings with this particular rival: the
    # residuals from the first coach's side. Empty when they've never met.
    def head_to_head(coach_id, rival_id)
      head_to_head_by_pair.fetch([ coach_id, rival_id ], [])
    end

    # How many points of margin the coaches add to a game, from the first
    # coach's side: each one's carryover (halved when both are users) plus
    # their own meetings. Either id may be nil (a CPU team contributes zero).
    def matchup_margin(coach_id, rival_id)
      return margin_points(coach_id) - margin_points(rival_id) if coach_id.nil? || rival_id.nil?

      USER_VS_USER_WEIGHT * (margin_points(coach_id) - margin_points(rival_id)) + head_to_head_points(coach_id, rival_id)
    end

    # matchup_margin in room-rating points, which WinTotals::Calculator works in.
    def matchup_rating_points(coach_id, rival_id)
      matchup_margin(coach_id, rival_id) / BigGameBreakdown::LineMaker::POINTS_PER_RATING_POINT
    end

    # The earlier meetings' average miss, shrunk by how few there are.
    def head_to_head_points(coach_id, rival_id)
      values = head_to_head(coach_id, rival_id)
      return 0.0 if values.empty?

      values.sum(0.0) / (values.size + HEAD_TO_HEAD_PRIOR_GAMES)
    end

    private

    def residuals_by_coach
      @residuals_by_coach ||= earlier_season_makers.each_with_object({}) do |maker, memo|
        maker.residuals_by_coach.each { |coach_id, values| (memo[coach_id] ||= []).concat(values) }
      end
    end

    def head_to_head_by_pair
      @head_to_head_by_pair ||= earlier_season_makers.each_with_object({}) do |maker, memo|
        maker.head_to_head_residuals.each { |pair, values| (memo[pair] ||= []).concat(values) }
      end
    end

    def earlier_season_makers
      @earlier_season_makers ||= @season.dynasty.seasons.where("year < ?", @season.year).order(:year).map do |earlier|
        BigGameBreakdown::LineMaker.new(earlier)
      end
    end
  end
end
