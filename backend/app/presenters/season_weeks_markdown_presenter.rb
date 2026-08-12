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
      "Results Recap & Rival Matchups — Deep dive into the highlighted games.",
      "Around the #{conference_label} — Quick hits on other conference games.",
      "Injury Report — Who's banged up, who's expected back, and how it affects the depth chart (if any injuries are active).",
      "Winners & Losers - the hosts each pick 1 team/player who won the week, and 1 who los",
      "Top 25 Poll Watch — Discuss rankings and national standing shifts (if focused teams are included)",
      "Week #{next_number} Preview — Look ahead to next week's opponents and the hosts make predictions"
    ]
  end

  def conference_label
    conferences = @data[:season][:coached_conferences]
    conferences.blank? ? "Conference" : conferences.join(" / ")
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

    if week_data[:conference_results].present?
      lines << "## 🌴 AROUND THE #{conference_label.upcase}"
      lines << ""
      lines.concat(conference_scoreboard_lines(week_data[:conference_results]))
    end

    lines.concat(conference_top_25_lines(week_data[:conference_top_25]))
    lines.concat(conference_heisman_lines(week_data[:conference_heisman_watch]))

    lines
  end

  def conference_scoreboard_lines(results)
    lines = results.map do |game|
      "- #{game[:away][:name]} #{game[:result][:away_score]} @ #{game[:home][:name]} #{game[:result][:home_score]}"
    end
    lines << ""
    lines
  end

  # Only rendered when a conference rival actually moved in the poll this
  # week — silent otherwise, per producer note: no filler when there's
  # nothing to report.
  def conference_top_25_lines(rankings)
    return [] if rankings.blank?

    lines = [ "## 🏆 TOP 25 WATCH — AROUND THE #{conference_label.upcase}", "" ]
    rankings.each { |ranking| lines << "- #{ranking[:college][:name]}: #{ranking_line(ranking)}" }
    lines << ""
    lines
  end

  # Only rendered when a conference rival's player actually joined or left
  # the Heisman watch this week — silent otherwise.
  def conference_heisman_lines(candidates)
    return [] if candidates.blank?

    lines = [ "## 🎖️ HEISMAN WATCH — AROUND THE #{conference_label.upcase}", "" ]
    candidates.each do |candidate|
      lines << "- #{candidate[:student][:name]} (#{candidate[:student][:position]}, #{candidate[:college][:name]}): " \
               "#{heisman_status_line(candidate[:status])}"
    end
    lines << ""
    lines
  end

  def heisman_status_line(status)
    case status
    when "added" then "Added to the Heisman watch this week"
    when "dropped" then "Dropped off the Heisman watch"
    else "Still in the Heisman conversation"
    end
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
    lines = [ "## #{team[:college][:name]} (Coach: #{team[:coach][:name]})" ]
    scheme_line = coach_scheme_line(team[:coach])
    lines << "*#{scheme_line}*" if scheme_line
    lines << "**Record entering week:** #{record[:wins]}-#{record[:losses]}"
    lines << "**Ranking:** #{ranking_line(team[:ranking])}"
    lines << ""

    lines << "### 🏆 Result"
    lines << "- #{game_result_line(team[:game])}"
    lines << ""

    lines.concat(team_stats_lines(team))

    if team[:game][:narrative_summary].present?
      lines << "### 📖 Narrative"
      lines << team[:game][:narrative_summary]
      lines << ""
    end

    if team[:game][:offensive_player_of_game] || team[:game][:defensive_player_of_game]
      lines << "### 🌟 Player of the Game"
      if team[:game][:offensive_player_of_game]
        lines << "- **Offense:** #{player_of_game_line(team[:game][:offensive_player_of_game])}"
      end
      if team[:game][:defensive_player_of_game]
        lines << "- **Defense:** #{player_of_game_line(team[:game][:defensive_player_of_game])}"
      end
      lines << ""
    end

    lines.concat(player_of_the_week_lines(team[:players_of_the_week]))
    lines.concat(top_performers_lines(team[:top_performers]))
    lines.concat(injury_report_lines(team[:injury_report]))

    lines << "### 📅 Next Up"
    lines.concat(next_up_lines(team[:next_game]))
    lines << ""
    lines
  end

  def coach_scheme_line(coach)
    parts = []
    parts << "Offensive Scheme: #{coach[:offensive_scheme]}" if coach[:offensive_scheme].present?
    parts << "Defensive Scheme: #{coach[:defensive_scheme]}" if coach[:defensive_scheme].present?
    return nil if parts.empty?

    parts.join(" | ")
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

  # Only rendered for a played game — silent for a bye/scheduled week, same
  # convention as narrative/player-of-the-game. Covers every CollegeGameStat
  # column (grouped into the usual box-score combo rows, e.g. "25/27" for
  # completions/attempts) rather than a curated subset.
  def team_stats_lines(team)
    stats = team[:game][:team_stats]
    return [] if stats.blank?

    team_name = team[:college][:name]
    opponent_name = team[:game][:opponent][:name]

    lines = [ "### 📊 Team Stats", "", "| Stat | #{team_name} | #{opponent_name} |", "| --- | --- | --- |" ]
    team_stats_rows.each do |label, formatter|
      lines << "| #{label} | #{formatter.call(stats[:team])} | #{formatter.call(stats[:opponent])} |"
    end
    lines << ""
    lines
  end

  def team_stats_rows
    [
      [ "First Downs", ->(s) { s[:first_downs] } ],
      [ "Total Offense", ->(s) { s[:total_offense] } ],
      [ "Total Yards (incl. Returns)", ->(s) { s[:total_yards] } ],
      [ "Total Plays", ->(s) { s[:total_plays] } ],
      [ "Yards / Play", ->(s) { s[:yards_per_play] } ],
      [ "Rushing", ->(s) { "#{s[:rushes]}-#{s[:rushing_yards]}-#{s[:rushing_tds]} TD (#{s[:yards_per_rush]} avg)" } ],
      [ "Passing", ->(s) { "#{s[:passing_completions]}/#{s[:passing_attempts]}-#{s[:passing_yards]}-#{s[:passing_tds]} TD (#{s[:yards_per_pass]} avg)" } ],
      [ "Turnovers", ->(s) { "#{s[:turnovers]} (#{s[:fumbles_lost]} FUM, #{s[:interceptions_thrown]} INT)" } ],
      [ "3rd Down", ->(s) { "#{s[:third_down_conversions]}/#{s[:third_down_attempts]}" } ],
      [ "4th Down", ->(s) { "#{s[:fourth_down_conversions]}/#{s[:fourth_down_attempts]}" } ],
      [ "Red Zone", ->(s) { "#{s[:red_zone_tds]} TD, #{s[:red_zone_field_goals]} FG (#{percentage_line(s[:red_zone_success_percentage])})" } ],
      [ "2-Point Conversions", ->(s) { "#{s[:two_point_conversions]}/#{s[:two_point_attempts]}" } ],
      [ "Punts", ->(s) { s[:punts] } ],
      [ "Punt Return Yards", ->(s) { s[:punt_return_yards] } ],
      [ "Kick Return Yards", ->(s) { s[:kick_return_yards] } ],
      [ "Penalties", ->(s) { "#{s[:penalties]}-#{s[:penalty_yards]} yds" } ],
      [ "Time of Possession", ->(s) { time_of_possession_line(s[:time_of_possession]) } ],
      [ "Points by Quarter", ->(s) { points_by_quarter_line(s) } ],
      [ "Final Score", ->(s) { s[:final_score] } ]
    ]
  end

  def percentage_line(value)
    value.present? ? "#{value}%" : "—"
  end

  def points_by_quarter_line(side)
    [ side[:points_in_quarter_1], side[:points_in_quarter_2], side[:points_in_quarter_3], side[:points_in_quarter_4] ]
      .map { |points| points || 0 }.join("-")
  end

  def time_of_possession_line(seconds)
    return "—" if seconds.blank?

    format("%d:%02d", seconds / 60, seconds % 60)
  end

  def opponent_line(opponent)
    where = opponent[:home] ? "vs" : "@"
    tag = opponent[:user_coached] ? " [fellow user-coached team]" : ""
    "#{where} #{opponent[:name]}#{tag}"
  end

  def next_up_lines(next_game)
    return [ "- Nothing scheduled beyond this point yet." ] unless next_game

    lines = [ "- Week #{next_game[:week_number]} — #{opponent_line(next_game[:opponent])}" ]
    lines.concat(scouting_report_lines(next_game[:scouting_report]))
    lines
  end

  def scouting_report_lines(report)
    return [] if report.blank?

    lines = []
    if report[:overall] || report[:offense] || report[:defense]
      lines << "  - Overall #{report[:overall] || '?'} | Offense #{report[:offense] || '?'} | Defense #{report[:defense] || '?'}"
    end
    lines << "  - Watch for on offense: #{scouting_player_line(report[:best_offensive_player])}" if report[:best_offensive_player]
    lines << "  - Watch for on defense: #{scouting_player_line(report[:best_defensive_player])}" if report[:best_defensive_player]
    lines
  end

  def scouting_player_line(player)
    "#{player[:name]} (#{player[:position]}, #{player[:overall]} OVR)"
  end

  # Only rendered when this team actually won a National/Conference Player
  # of the Week award this week — silent otherwise, same convention as
  # every other optional section.
  def player_of_the_week_lines(players_of_the_week)
    return [] unless players_of_the_week[:offensive] || players_of_the_week[:defensive]

    lines = [ "### 🏅 Player of the Week" ]
    lines << "- **Offense:** #{player_of_the_week_line(players_of_the_week[:offensive])}" if players_of_the_week[:offensive]
    lines << "- **Defense:** #{player_of_the_week_line(players_of_the_week[:defensive])}" if players_of_the_week[:defensive]
    lines << ""
    lines
  end

  def player_of_the_week_line(player)
    scope = player[:national] ? "National" : "#{player[:conference]} Conference"
    base = "#{scope} Player of the Week — #{player[:name]} (#{player[:position]})"
    player[:stat_line].present? ? "#{base}: #{player[:stat_line]}" : base
  end

  # Only rendered when this team has at least one currently-active injury —
  # silent otherwise, same convention as every other optional section.
  def injury_report_lines(injury_report)
    return [] if injury_report.blank?

    lines = [ "### 🚑 Injury Report" ]
    injury_report.each { |injury| lines << "- #{injury_report_line(injury)}" }
    lines << ""
    lines
  end

  def injury_report_line(injury)
    status = injury[:status] == "out_for_season" ? "out for the season" : injury[:status].tr("_", " ")
    "#{injury[:name]} (#{injury[:position]}) — #{injury[:description]} (Week #{injury[:injured_week_number]} injury, #{status})"
  end

  def player_of_game_line(player)
    base = "#{player[:name]} (#{player[:position]}, #{player[:college]})"
    player[:stat_line].present? ? "#{base}: #{player[:stat_line]}" : base
  end

  def top_performers_lines(top_performers)
    return [] if top_performers.blank?

    groups = [ top_performers[:team], top_performers[:opponent] ].compact.reject { |group| group[:performers].blank? }
    return [] if groups.empty?

    lines = [ "### ⭐ Top Performers" ]
    groups.each do |group|
      lines << "**#{group[:college][:name]}:**"
      group[:performers].each { |performer| lines << "- #{performer_line(performer)}" }
    end
    lines << ""
    lines
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
