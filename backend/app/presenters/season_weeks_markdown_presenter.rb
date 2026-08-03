# Renders the SeasonWeeksSerializer payload as Markdown, meant for feeding
# into an LLM-based podcast generator (e.g. NotebookLM) rather than JSON.
class SeasonWeeksMarkdownPresenter
  def initialize(data)
    @data = data
  end

  def to_markdown
    lines = []
    lines.concat(PodcastShow.directive_lines(show_name: show_name))
    lines.concat(PodcastShow.opening_script_lines(show_name: show_name, framing_hint: opening_framing_hint))
    lines.concat(PodcastShow.run_of_show_lines(segments))
    lines << "# 🎙️ WEEKLY BROADCAST DATA"
    lines << ""
    lines << "> #{producer_note}"
    lines << ""

    @data[:weeks].each_with_index do |week_data, index|
      lines.concat(week_section(week_data, primary: index.zero?))
    end

    lines.join("\n")
  end

  private

  def primary_week
    @data[:weeks].first
  end

  def show_name
    @data[:season][:dynasty]
  end

  def opening_framing_hint
    primary_week ? week_label(primary_week[:week]) : "this week's show"
  end

  def producer_note
    note = "PRODUCER NOTE: Welcome back to the studio, team. Below are your pre-show game notes for today's " \
           "taping — results, standings movement, and next matchups for our guys."

    older_weeks = @data[:weeks][1..]
    if older_weeks.present?
      labels = older_weeks.map { |week_data| week_label(week_data[:week]) }.join(", ")
      note += " #{labels} #{older_weeks.size == 1 ? 'is' : 'are'} included further down purely for background — " \
              "don't dwell on it."
    end

    note
  end

  def segments
    next_number = primary_week ? primary_week[:week][:number] + 1 : 1
    current_label = primary_week ? week_label(primary_week[:week]) : "This Week"

    [
      "#{current_label} Kickoff & Headlines",
      "Results Recap & Rival Matchups",
      "Winners & Losers",
      "Top 25 Poll Watch",
      "Week #{next_number} Preview"
    ]
  end

  def week_section(week_data, primary:)
    week = week_data[:week]
    lines = [ "---", "", "# 🏈 #{week_label(week).upcase}#{primary ? ' (CURRENT)' : ''}", "" ]
    lines.concat(at_a_glance_table(week_data[:teams]))

    week_data[:teams].each { |team| lines.concat(team_week_section(team)) }

    if week_data[:coached_matchups].any?
      lines << "## 🆚 MATCHUPS BETWEEN OUR COACHES THIS WEEK"
      lines << ""
      lines.concat(matchups_table(week_data[:coached_matchups]))
    end

    lines
  end

  def week_label(week)
    return "the Conference Championship" if week[:conference_championship]
    return week[:name] || "the postseason" if week[:post_season]

    "Week #{week[:number]}"
  end

  def at_a_glance_table(teams)
    lines = [ "## 📊 THIS WEEK AT A GLANCE", "" ]
    lines << "| Team | Record Entering | Ranking | Result |"
    lines << "| --- | --- | --- | --- |"
    teams.each do |team|
      record = team[:record_entering_week]
      lines << "| #{team[:college][:name]} | #{record[:wins]}-#{record[:losses]} | " \
               "#{ranking_line(team[:ranking])} | #{glance_result(team[:game])} |"
    end
    lines << ""
    lines
  end

  def glance_result(game)
    case game[:status]
    when "bye" then "Bye"
    when "scheduled" then "#{opponent_line(game[:opponent])} (upcoming)"
    when "final"
      result = game[:result]
      "#{result[:won] ? 'W' : 'L'} #{result[:team_score]}-#{result[:opponent_score]} #{opponent_line(game[:opponent])}"
    end
  end

  def team_week_section(team)
    record = team[:record_entering_week]
    lines = [
      "## #{team[:college][:name]} (Coach: #{team[:coach][:name]})",
      "**Record entering week:** #{record[:wins]}-#{record[:losses]}",
      "**Ranking:** #{ranking_line(team[:ranking])}",
      ""
    ]

    lines << "### 🏆 Result"
    lines << "- #{game_result_line(team[:game])}"
    lines << ""

    if team[:top_performers].present?
      lines << "### ⭐ Top Performers"
      team[:top_performers].each { |performer| lines << "- #{performer_line(performer)}" }
      lines << ""
    end

    lines << "### 📅 Next Up"
    lines << "- #{next_game_line(team[:next_game])}"
    lines << ""
    lines
  end

  def ranking_line(ranking)
    case ranking[:status]
    when "entered_top_25" then "Just cracked the Top 25 at ##{ranking[:current_rank]}"
    when "dropped_out_of_top_25" then "Fell out of the Top 25 (was ##{ranking[:previous_rank]})"
    when "moved_up" then "##{ranking[:current_rank]} (up from ##{ranking[:previous_rank]})"
    when "moved_down" then "##{ranking[:current_rank]} (down from ##{ranking[:previous_rank]})"
    when "steady" then "##{ranking[:current_rank]} (unchanged)"
    else "Unranked"
    end
  end

  def game_result_line(game)
    case game[:status]
    when "bye"
      "Bye week — no game."
    when "scheduled"
      "#{opponent_line(game[:opponent])} — not yet played."
    when "final"
      result = game[:result]
      outcome = result[:won] ? "W" : "L"
      "#{outcome} #{result[:team_score]}-#{result[:opponent_score]} #{opponent_line(game[:opponent])}"
    end
  end

  def opponent_line(opponent)
    where = opponent[:home] ? "vs" : "@"
    tag = opponent[:user_coached] ? " [fellow user-coached team]" : ""
    "#{where} #{opponent[:name]}#{tag}"
  end

  def next_game_line(next_game)
    return "Nothing scheduled beyond this point yet." unless next_game

    "Week #{next_game[:week_number]} — #{opponent_line(next_game[:opponent])}"
  end

  def performer_line(performer)
    stat_line = performer[:stats].map { |key, value| "#{value} #{key.to_s.tr('_', ' ')}" }.join(", ")
    "#{performer[:name]} (#{performer[:position]}): #{stat_line}"
  end

  def matchups_table(matchups)
    lines = [ "| Home | Away | Result |", "| --- | --- | --- |" ]
    matchups.each { |m| lines << "| #{m[:home][:name]} | #{m[:away][:name]} | #{matchup_result(m)} |" }
    lines << ""
    lines
  end

  def matchup_result(matchup)
    return "Upcoming" unless matchup[:result]

    "#{matchup[:result][:team_score]} - #{matchup[:result][:opponent_score]}"
  end
end
