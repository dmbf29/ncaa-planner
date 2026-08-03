# Renders the SeasonPreviewSerializer payload as Markdown, meant for feeding
# into an LLM-based podcast generator (e.g. NotebookLM) rather than JSON.
class SeasonPreviewMarkdownPresenter
  def initialize(data)
    @data = data
  end

  def to_markdown
    lines = []
    lines.concat(PodcastShow.directive_lines(show_name: show_name))
    lines.concat(PodcastShow.opening_script_lines(show_name: show_name, framing_hint: "the season ahead"))
    lines.concat(PodcastShow.run_of_show_lines(segments))
    lines << "# 🏈 SEASON PREVIEW: #{show_name} — #{@data[:season][:year]}"
    lines << ""
    lines << "> #{producer_note}"
    lines << ""
    lines.concat(at_a_glance_table)

    @data[:teams].each { |team| lines.concat(team_section(team)) }

    lines.concat(conference_landscape_section)

    if @data[:coached_matchups].any?
      lines << "---"
      lines << ""
      lines << "## 🆚 MATCHUPS BETWEEN OUR COACHES THIS SEASON"
      lines << ""
      lines.concat(matchups_table(@data[:coached_matchups]))
    end

    lines.concat(week_one_preview_section)

    lines.join("\n")
  end

  private

  def show_name
    @data[:season][:dynasty]
  end

  def conferences
    @conferences ||= @data[:teams].filter_map { |team| team[:college][:conference] }.uniq.join(" and ")
  end

  def producer_note
    "PRODUCER NOTE: Welcome back to the studio, team. Below is your pre-show research briefing and game notes " \
      "for today's taping — season ratings, players to watch, and the Week 1 slate."
  end

  def segments
    headline = conferences.present? ? "#{conferences} Headlines" : "League Headlines"
    [
      "Season Kickoff & #{headline}",
      "Roster Breakdown & Key Impact Players",
      "Strengths, Weaknesses, and Positional Battles",
      "Conference Championship & Season Predictions",
      "Week 1 Kickoff Game Previews"
    ]
  end

  def week_one_preview_section
    return [] if @data[:week_one_games].blank?

    lines = [ "## 🏟️ WEEK 1 PREVIEW", "" ]
    @data[:week_one_games].each do |game|
      lines << "- **#{game[:college][:name]}** (Coach: #{game[:coach][:name]}): #{week_one_opponent_line(game[:opponent])}"
    end
    lines << ""
    lines
  end

  def week_one_opponent_line(opponent)
    return "Bye week." unless opponent

    where = opponent[:home] ? "vs" : "@"
    overall = opponent[:overall] ? " (#{opponent[:overall]} OVR)" : ""
    "#{where} #{opponent[:name]}#{overall}"
  end

  def conference_landscape_section
    return [] if @data[:conference_landscape].blank?

    lines = []
    @data[:conference_landscape].each do |group|
      next if group[:teams].blank?

      lines << "---"
      lines << ""
      lines << "## 🏟️ #{group[:conference].upcase} LANDSCAPE"
      lines << ""
      lines << "The rest of the #{group[:conference]}, for context on who our coached teams have to get through:"
      lines << ""
      lines << "| Team | Overall | Offense | Defense | Conference Rank | National Rank |"
      lines << "| --- | --- | --- | --- | --- | --- |"
      group[:teams].each do |team|
        lines << "| #{team[:college][:name]} | #{team[:overall]} | #{team[:offense]} | #{team[:defense]} | " \
                 "#{ordinal(team[:conference_rank])} | #{ordinal(team[:national_rank])} |"
      end
      lines << ""
    end
    lines
  end

  def at_a_glance_table
    lines = [ "## 📊 AT A GLANCE", "" ]
    lines << "| Team | Coach | Conference | Overall | Offense | Defense | National Rank | Conference Rank |"
    lines << "| --- | --- | --- | --- | --- | --- | --- | --- |"
    @data[:teams].each do |team|
      ctx = team[:national_context]
      ratings = team[:ratings]
      lines << "| #{team[:college][:name]} | #{team[:coach][:name]} | #{team[:college][:conference]} | " \
               "#{ratings[:overall]} | #{ratings[:offense]} | #{ratings[:defense]} | " \
               "#{ordinal(ctx[:overall_rank])} of #{ctx[:total_colleges]} | " \
               "#{ordinal(ctx[:conference_rank])} of #{ctx[:conference_size]} |"
    end
    lines << ""
    lines
  end

  def team_section(team)
    lines = []
    lines << "---"
    lines << ""
    lines << "## 🎯 #{team[:college][:name]} (Coach: #{team[:coach][:name]})"
    lines << "**Conference:** #{team[:college][:conference]}" if team[:college][:conference]
    ratings = team[:ratings]
    lines << "**Ratings:** Overall #{ratings[:overall]}, Offense #{ratings[:offense]}, Defense #{ratings[:defense]}, " \
             "Prestige #{ratings[:prestige]}"
    lines << "**National Context:** #{national_context_line(team[:national_context])}"
    lines << ""

    lines.concat(player_to_watch_section(team[:player_to_watch]))
    lines.concat(key_players_section(team[:key_players]))
    lines.concat(extremes_section("💪 Strengths", team[:strengths]))
    lines.concat(extremes_section("⚠️ Weaknesses", team[:weaknesses]))
    lines.concat(schedule_section(team[:schedule_preview]))

    lines
  end

  def national_context_line(context)
    "Ranked #{ordinal(context[:overall_rank])} of #{context[:total_colleges]} colleges overall — " \
      "#{ordinal(context[:conference_rank])} of #{context[:conference_size]} in conference"
  end

  def player_to_watch_section(player)
    return [] unless player

    reason = player[:reason] == "breakout_candidate" ? "breakout candidate" : "top returning talent"
    [
      "### ⭐ Player to Watch",
      "- #{player[:name]} (#{player[:position]}, #{player[:overall]} OVR, " \
      "#{player[:class_year]}) — #{reason}",
      ""
    ]
  end

  def key_players_section(key_players)
    lines = [ "### 🔑 Key Players", "", "**Offense:**" ]
    lines.concat(player_bullets(key_players[:offense]))
    lines << ""
    lines << "**Defense:**"
    lines.concat(player_bullets(key_players[:defense]))
    lines << ""
    lines
  end

  def player_bullets(players)
    return [ "- None listed" ] if players.blank?

    players.map { |p| "- #{p[:name]} (#{p[:position]}, #{p[:overall]})" }
  end

  def extremes_section(label, entries)
    return [] if entries.blank?

    lines = [ "### #{label}" ]
    entries.each { |e| lines << "- #{e[:position_group]} (#{e[:average]} avg)" }
    lines << ""
    lines
  end

  def schedule_section(schedule)
    lines = [ "### 📅 Schedule Notes" ]
    lines << "- **Opener:** #{game_line(schedule[:opener])}" if schedule[:opener]
    lines << "- **Toughest Matchup:** #{game_line(schedule[:toughest_matchup])}" if schedule[:toughest_matchup]
    lines << "- **Bye Weeks:** #{schedule[:bye_weeks].join(', ')}" if schedule[:bye_weeks].present?

    if schedule[:rivalry_games].present?
      lines << "- **Rivalry Games:**"
      schedule[:rivalry_games].each { |g| lines << "  - #{game_line(g)}" }
    end
    lines << ""
    lines
  end

  def game_line(game)
    where = game[:home] ? "vs" : "@"
    overall = game[:opponent_overall] ? " (#{game[:opponent_overall]} OVR)" : ""
    "#{where} #{game[:opponent][:name]}#{overall} — Week #{game[:week_number]}"
  end

  def matchups_table(matchups)
    lines = [ "| Week | Home | Away |", "| --- | --- | --- |" ]
    matchups.each { |m| lines << "| #{m[:week_number]} | #{m[:home][:name]} | #{m[:away][:name]} |" }
    lines << ""
    lines
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
end
