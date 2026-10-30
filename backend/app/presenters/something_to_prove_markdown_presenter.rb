# Renders SomethingToProveSerializer's hash as the source document for the season opener's "Something to Prove"
# segment. It is only facts, each with what it was ranked against; deciding which one is the team's thing to prove is
# the hosts' job. Empty string when there is nothing to say.
class SomethingToProveMarkdownPresenter
  STAT_LABELS = {
    pass_yards_per_game: "passing yards a game", rush_yards_per_game: "rushing yards a game",
    total_yards_per_game: "total offense a game", yards_per_play: "yards per play", pass_tds_per_game: "passing touchdowns a game",
    total_yards_allowed_per_game: "total yards allowed a game", pass_yards_allowed_per_game: "passing yards allowed a game",
    rush_yards_allowed_per_game: "rushing yards allowed a game", sacks_per_game: "sacks a game"
  }.freeze

  def initialize(data)
    @data = data
  end

  def to_markdown
    return "" if @data[:teams].empty?

    lines = [ "# SOMETHING TO PROVE — #{@data[:year]} SEASON OPENER", "" ]
    lines << "> Producer note (DO NOT READ ALOUD): this is the fact sheet for one segment of about two minutes, right after the " \
             "card. For each team below, in the order given, name the ONE thing it most needs to fix or show this season " \
             "(about twenty-five seconds each, both hosts), chosen from the facts: a weakness the numbers show, the kind of " \
             "game it keeps losing, or, for a team with no losses to point to, the contrast between its best and its worst " \
             "ranking. A team that changed divisions or conferences gets the move named once, with who it now shares a division with. Say each ranking with the group it was ranked against, exactly as written, and never rank a team " \
             "against a bigger group than the one named. Never present any of it as new. Keep it forward-looking: what " \
             "this season has to answer, not a replay of last year."
    lines << ""
    @data[:teams].each { |team| lines.concat(team_lines(team)) }
    lines.join("\n").rstrip + "\n"
  end

  private

  def team_lines(team)
    record = team[:record]
    lines = [ "## #{team[:college]}#{" (Coach #{team[:coach]})" if team[:coach]}", "" ]
    lines << "- Last season (#{@data[:previous_year]}, in the #{team[:conference_last_season]}): #{record[:wins]}-#{record[:losses]}"
    lines << "- New to the #{team[:conference_now]} this season, from the #{team[:new_conference_from]}. Last season's numbers below were put up in the #{team[:new_conference_from]}." if team[:new_conference_from]
    lines.concat(division_lines(team))
    lines.concat(scoring_lines(team[:scoring]))
    lines.concat(loss_lines(team[:losses]))
    lines.concat(conference_lines(team[:conference_stats]))
    lines.concat(departed_lines(team[:departed]))
    lines << ""
  end

  def division_lines(team)
    division = team[:division]
    return [] unless division

    where = division[:moved_from] ? "moves from the #{division[:moved_from]} to the #{division[:name]} division this season" : "plays in the #{division[:name]} division"
    [ "- Division: #{where}, with #{division[:mates].join(', ')}. The #{team[:conference_now]} sends its two division winners to the " \
      "conference championship game, so these are the teams it has to beat just to get there." ]
  end

  def scoring_lines(scoring)
    return [] unless scoring

    [ "- Scoring (nationally, ranked among #{scoring[:of]} schools, 1 = best): #{scoring[:points_scored_per_game]} points a game " \
      "(#{ordinal(scoring[:points_scored_rank])}), #{scoring[:points_allowed_per_game]} allowed a game (#{ordinal(scoring[:points_allowed_rank])})" ]
  end

  def loss_lines(losses)
    return [ "- Losses: none" ] if losses.empty?

    one_score = losses.count { |loss| loss[:one_score] }
    list = losses.map { |loss| "#{loss[:opponent]} #{loss[:score]} (#{loss[:site]}#{', one score' if loss[:one_score]})" }
    [ "- Losses (#{losses.size}, #{one_score} by one score or less): #{list.join('; ')}" ]
  end

  def conference_lines(conference)
    return [] unless conference

    rows = conference[:stats].map do |name, stat|
      "#{STAT_LABELS.fetch(name)} #{stat[:value]} (#{ordinal(stat[:rank])})"
    end
    [ "- Season totals (ranked ONLY among the #{conference[:of]} #{conference[:conference]} teams, 1 = best; say \"in the #{conference[:conference]}\" " \
      "every time, never \"nationally\"): #{rows.join('; ')}" ]
  end

  def departed_lines(departed)
    return [] if departed.blank?

    parts = []
    parts << "top rusher #{departed[:rusher][:name]} (#{departed[:rusher][:yards]} rushing yards)" if departed[:rusher]
    parts << "top passer #{departed[:passer][:name]} (#{departed[:passer][:yards]} passing yards)" if departed[:passer]
    [ "- No longer on the roster (graduated or gone): #{parts.join('; ')}. One clause at most, not a roster review." ]
  end

  def ordinal(number)
    suffix = number.between?(11, 13) ? "th" : { 1 => "st", 2 => "nd", 3 => "rd" }.fetch(number % 10, "th")
    "#{number}#{suffix}"
  end
end
