# Renders the MidseasonReportCardSerializer payload as Markdown, meant for
# feeding into an LLM-based podcast generator (e.g. NotebookLM) rather than
# JSON. The app never computes a letter grade anywhere in this file — see
# GRADING_RULES below, which exist specifically to keep it that way.
class MidseasonReportCardMarkdownPresenter
  PROJECTION_LABELS = { likely_win: "likely win", likely_loss: "likely loss", coin_flip: "coin flip" }.freeze

  STAT_LABELS = {
    points_scored: "Points scored", total_offensive_yards: "Total yards", yards_per_play: "Yards per play",
    passing_yards: "Passing yards", passing_touchdowns: "Passing TDs", rushing_yards: "Rushing yards",
    rushing_touchdowns: "Rushing TDs", first_downs: "First downs",
    points_allowed: "Points allowed", total_yards_allowed: "Total yards allowed",
    passing_yards_allowed: "Passing yards allowed", rushing_yards_allowed: "Rushing yards allowed",
    defensive_sacks: "Sacks", fumble_recoveries: "Fumble recoveries", defensive_interceptions: "Interceptions"
  }.freeze

  GRADING_RULES = [
    "For every team, BOTH hosts must independently state their own letter grade (A+ through F) with real " \
    "reasoning. They are not required to agree — a split grade is good radio, not a problem to resolve.",
    "Ground every grade in the evidence below: the record itself, whether the team is ahead of or behind the " \
    "pace implied by their preseason Vegas number, any signature win or bad loss, the team stats (note how many " \
    "games each team has actually played — a team coming off a bye has fewer numbers on the board, don't " \
    "penalize them for that), and where they sit in the conference standings.",
    "Arlis tends to grade on the eye test and the storyline — expectations, drama, signature moments. Ty tends " \
    "to grade on the scoreboard and the pace against the preseason number. Let that tension show."
  ].freeze

  PACE_TONE_RULES = [
    "When talking about the preseason Vegas number, don't say \"probability,\" \"model,\" or \"algorithm\" — " \
    "say things like \"on pace,\" \"ahead of schedule,\" \"outkicking the number Vegas had them at,\" or " \
    "\"underwater against their preseason total.\""
  ].freeze

  def initialize(data)
    @data = data
  end

  def to_markdown
    lines = []
    lines.concat(PodcastShow.directive_lines(show_name: show_name))
    lines.concat(grading_format_lines)
    lines.concat(pace_tone_lines)
    lines.concat(PodcastShow.opening_script_lines(show_name: show_name, framing_hint: "how our coached teams are actually performing at the midway point of the season"))
    lines.concat(PodcastShow.run_of_show_lines(segments))
    lines << "# 📋 MIDSEASON REPORT CARDS — #{show_name} — #{@data[:season][:year]}"
    lines << ""
    lines << "> #{producer_note}"
    lines << ""

    @data[:teams].each { |team| lines.concat(team_section(team)) }

    lines.concat(improve_your_grade_section)

    lines.join("\n")
  end

  private

  def show_name
    @data[:season][:dynasty]
  end

  def producer_note
    "PRODUCER NOTE: Midseason grades for our coached teams — the app never assigns a letter grade, that's " \
      "entirely on the hosts. Use the record, the pace against the preseason Vegas number, any signature win or " \
      "bad loss, the team stats (season totals plus per-game, since bye weeks mean unequal games played), and " \
      "the conference standing as evidence. Ends with a look at each team's remaining schedule so the hosts can " \
      "say what it'll take to move the needle."
  end

  def grading_format_lines
    lines = [ "## 📋 GRADING FORMAT (PRODUCER NOTE, DO NOT READ ALOUD)", "" ]
    GRADING_RULES.each { |rule| lines << "- #{rule}" }
    lines << ""
    lines
  end

  def pace_tone_lines
    lines = [ "## 🎰 TONE — NO STATS-SPEAK ON THE PACE TALK (PRODUCER NOTE, DO NOT READ ALOUD)", "" ]
    PACE_TONE_RULES.each { |rule| lines << "- #{rule}" }
    lines << ""
    lines
  end

  def segments
    team_segments = @data[:teams].map { |t| "#{t[:college][:name]} Midseason Report Card" }
    team_segments + [ "How to Improve Your Grade: The Rest of the Season" ]
  end

  def team_section(team)
    lines = []
    lines << "---"
    lines << ""
    lines << "## 📋 #{team[:college][:name]} (Coach: #{team[:coach][:name]})"
    lines << "**Conference:** #{team[:college][:conference]}" if team[:college][:conference]
    lines << "**Ratings:** #{ratings_line(team[:ratings])}"
    lines << "**Record:** #{record_line(team[:record])}"
    lines << "**Conference Standing:** #{standing_line(team[:conference_standing])}"
    lines << "> ⚠️ #{team[:record_note]}" if team[:record_note]
    lines << ""

    lines.concat(pace_section(team[:vegas_context]))
    lines.concat(notable_results_section(team[:notable_results]))
    lines.concat(team_stats_section(team[:team_stats]))
    lines.concat(played_schedule_section(team[:played_schedule]))

    lines
  end

  def ratings_line(ratings)
    return "—" unless ratings

    "Overall #{ratings[:overall]}, Offense #{ratings[:offense]}, Defense #{ratings[:defense]}"
  end

  def record_line(record)
    return "—" unless record

    "#{record[:wins]}-#{record[:losses]} (#{record[:conference_wins]}-#{record[:conference_losses]} conf)"
  end

  def standing_line(standing)
    return "—" unless standing

    "#{ordinal(standing[:rank])} in the conference (of #{standing[:of]})"
  end

  def pace_section(context)
    return [] unless context

    lines = [ "### 🎯 Pace Check", "" ]
    lines << "- Preseason number: #{format_line(context[:preseason_win_total])} wins"
    losses_so_far = context[:games_played] - context[:wins_so_far]
    lines << "- Actual: #{context[:wins_so_far]}-#{losses_so_far} through #{context[:games_played]} " \
             "#{context[:games_played] == 1 ? 'game' : 'games'}"
    lines << "- #{pace_line(context)}"
    lines << ""
    lines
  end

  def pace_line(context)
    diff = context[:pace_differential]
    pace_read = if diff.positive?
      "ahead of the pace needed to hit that number"
    elsif diff.negative?
      "behind the pace needed to hit that number"
    else
      "right on pace"
    end

    trend = if context[:updated_projected_wins] > context[:preseason_win_total]
      "trending OVER the preseason number"
    elsif context[:updated_projected_wins] < context[:preseason_win_total]
      "trending UNDER the preseason number"
    else
      "trending right at the preseason number"
    end

    "#{pace_read.capitalize}, #{trend} — roughly #{context[:updated_projected_wins].round(1)} wins if the rest of the schedule plays to form"
  end

  def notable_results_section(notable)
    return [] if notable.blank?

    lines = []
    if notable[:signature_wins].present?
      lines << "### 🌟 Signature Wins (beat a team they had no business beating)"
      lines << ""
      notable[:signature_wins].each { |g| lines << "- #{notable_result_line(g)}" }
      lines << ""
    end

    if notable[:bad_losses].present?
      lines << "### 💀 Bad Losses (lost to a team they had no business losing to)"
      lines << ""
      notable[:bad_losses].each { |g| lines << "- #{notable_result_line(g)}" }
      lines << ""
    end
    lines
  end

  def notable_result_line(game)
    where = game[:home] ? "vs" : "@"
    "Week #{game[:week_number]} #{where} #{game[:opponent][:name]} (#{game[:score][:team]}-#{game[:score][:opponent]})"
  end

  def team_stats_section(stats)
    return [] unless stats

    lines = [ "### 📊 Team Stats (#{stats[:games_played]} #{stats[:games_played] == 1 ? 'game' : 'games'} played)", "" ]
    lines << "**Offense:**"
    lines.concat(stat_group_bullets(stats[:offense]))
    lines << ""
    lines << "**Defense:**"
    lines.concat(stat_group_bullets(stats[:defense]))
    lines << ""
    lines
  end

  def stat_group_bullets(group)
    return [ "- No stats logged yet" ] if group.blank? || group.values.all?(&:nil?)

    group.filter_map do |key, value|
      next unless value

      label = STAT_LABELS.fetch(key, key.to_s)
      rank = rank_suffix(value[:conference_rank])
      if value.key?(:rate)
        "- #{label}: #{value[:rate]}#{rank}"
      else
        "- #{label}: #{value[:total]} total (#{value[:per_game]}/game)#{rank}"
      end
    end
  end

  def rank_suffix(rank)
    return "" unless rank

    " — #{ordinal(rank[:rank])} in the conference (of #{rank[:of]})"
  end

  def played_schedule_section(schedule)
    lines = [ "### 🗓️ Results So Far", "" ]
    return lines + [ "- No games played yet.", "" ] if schedule.blank?

    schedule.each { |g| lines << played_game_line(g) }
    lines << ""
    lines
  end

  def played_game_line(g)
    where = g[:home] ? "vs" : "@"
    outcome = g[:result][:won] ? "W" : "L"
    score = "#{g[:result][:team_score]}-#{g[:result][:opponent_score]}"
    opp_ratings = g[:opponent_ratings]
    opp_summary = opp_ratings ? " (#{opp_ratings[:overall]} OVR)" : ""
    label = PROJECTION_LABELS.fetch(g[:pregame_projection], "")
    "- #{outcome} #{score} — Week #{g[:week_number]} #{where} #{g[:opponent][:name]}#{opp_summary} — preseason had this as a #{label}"
  end

  def improve_your_grade_section
    lines = [ "---", "", "## 📈 HOW TO IMPROVE YOUR GRADE: THE REST OF THE SEASON", "" ]
    @data[:teams].each { |team| lines.concat(remaining_schedule_bullets(team)) }
    lines
  end

  def remaining_schedule_bullets(team)
    lines = [ "**#{team[:college][:name]}:**" ]
    schedule = team[:remaining_schedule]
    if schedule.blank?
      lines << "- Regular season is in the books."
    else
      schedule.each { |g| lines << remaining_game_line(g) }
    end
    lines << ""
    lines
  end

  def remaining_game_line(g)
    where = g[:home] ? "vs" : "@"
    opp_ratings = g[:opponent_ratings]
    opp_summary = opp_ratings ? " (#{opp_ratings[:overall]} OVR)" : ""
    label = PROJECTION_LABELS.fetch(g[:projection], "")
    "- Week #{g[:week_number]} #{where} #{g[:opponent][:name]}#{opp_summary} — #{label}"
  end

  def ordinal(number)
    return "unranked" if number.nil?
    return "#{number}th" if (11..13).cover?(number % 100)

    case number % 10
    when 1 then "#{number}st"
    when 2 then "#{number}nd"
    when 3 then "#{number}rd"
    else "#{number}th"
    end
  end

  def format_line(number)
    return "—" unless number

    number % 1 == 0 ? "#{number.to_i}.0" : number.to_s
  end
end
