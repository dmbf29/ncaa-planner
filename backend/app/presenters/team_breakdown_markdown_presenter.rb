# Renders the TeamBreakdownSerializer payload as Markdown, meant for
# feeding into an LLM-based podcast generator (e.g. NotebookLM) rather than
# JSON.
class TeamBreakdownMarkdownPresenter
  def initialize(data)
    @data = data
  end

  def to_markdown
    lines = []
    lines.concat(PodcastShow.directive_lines(show_name: show_name))
    lines.concat(PodcastShow.opening_script_lines(show_name: show_name, framing_hint: "the roster, position by position"))
    lines.concat(PodcastShow.run_of_show_lines(@data[:positions].map { |p| p[:position_group] }))
    lines << "# 🏈 ROSTER BREAKDOWN: #{show_name} — #{@data[:season][:year]}"
    lines << ""
    lines << "> #{producer_note}"
    lines << ""
    lines.concat(data_coverage_section)

    @data[:positions].each { |position| lines.concat(position_section(position)) }

    lines.join("\n")
  end

  private

  def show_name
    @data[:season][:dynasty]
  end

  def producer_note
    "PRODUCER NOTE: Position-by-position breakdown of our roster ahead of the season — who's set, who needs " \
      "work, NIL investment by position, and how we stack up against the rest of the conference. No games have " \
      "been played yet, so this is entirely roster/recruiting/spending analysis."
  end

  def data_coverage_section
    coverage = @data[:data_coverage]
    lines = [ "## 📋 DATA COVERAGE (PRODUCER NOTE, DO NOT READ ALOUD)", "" ]
    lines << "> #{coverage[:note]}"
    lines << ">"
    lines << "> **Rosters we have:** #{coverage[:rostered_colleges].join(', ')}"
    lines << "> **Colleges with NIL spend data:** #{coverage[:colleges_with_nil_spend_data]}"
    lines << ""
    lines
  end

  def position_section(position)
    lines = []
    lines << "---"
    lines << ""
    lines << "## 🎯 #{position[:position_group].upcase}"
    lines << ""
    lines.concat(our_teams_table(position[:our_teams]))
    lines.concat(headline_bullets(position))
    lines.concat(conference_section(position[:conference]))
    lines
  end

  def our_teams_table(teams)
    lines = [ "**Our Teams:**", "" ]
    lines << "| Team | Coach | Best Player | Avg Rating | Conf Rank | NIL Spend | All-Americans |"
    lines << "| --- | --- | --- | --- | --- | --- | --- |"
    teams.each do |team|
      lines << "| #{team[:college][:name]} | #{team[:coach][:name]} | #{player_line(team[:best_player])} | " \
               "#{team[:average_rating] || '—'} | #{conference_rank_line(team[:conference_rank])} | " \
               "#{currency(team[:nil_spend])} | #{all_americans_line(team[:all_americans])} |"
    end
    lines << ""
    lines
  end

  def conference_rank_line(rank)
    return "—" unless rank

    "#{rank[:rank]} of #{rank[:of]}"
  end

  def player_line(player)
    return "—" unless player

    "#{player[:name]} (#{player[:overall]} OVR, #{player[:class_year]})"
  end

  def all_americans_line(all_americans)
    return "—" if all_americans.blank?

    all_americans.map { |aa| "#{aa[:name]} (#{honor_label(aa)})" }.join(", ")
  end

  def honor_label(all_american)
    scope = all_american[:national] ? "National" : all_american[:conference]
    tier = all_american[:tier] == 1 ? "1st Team" : "2nd Team"
    preseason = all_american[:preseason] ? "Preseason " : ""
    "#{preseason}#{scope} #{tier}"
  end

  def headline_bullets(position)
    lines = [ "**Storylines:**", "" ]
    lines << "- 💪 **Strongest of ours:** #{extreme_line(position[:strongest_of_ours])}" if position[:strongest_of_ours]
    lines << "- ⚠️ **Should be worried:** #{extreme_line(position[:team_to_worry_about])}" if position[:team_to_worry_about]
    lines << "- 💰 **Spending the most:** #{extreme_line(position[:most_nil_invested_of_ours], unit: 'NIL')}" if position[:most_nil_invested_of_ours]
    lines << "- 🪙 **Should spend more:** #{extreme_line(position[:should_spend_more], unit: 'NIL')}" if position[:should_spend_more]
    lines << ""
    lines
  end

  def extreme_line(extreme, unit: nil)
    label = unit == "NIL" ? currency(extreme[:value]) : "#{extreme[:value]} avg"
    "#{extreme[:college][:name]} (#{label})"
  end

  def conference_section(conference)
    lines = [ "**Around the Conference:**", "" ]

    if conference[:average_rating_leaderboard].present?
      lines << "- 📊 **Average rating leaders:** #{rating_leaderboard_line(conference[:average_rating_leaderboard])}"
    end

    if conference[:best_rated_player]
      p = conference[:best_rated_player]
      coached_note = p[:coached_by_us] ? " — one of ours" : ""
      lines << "- 🏆 **Best rated in the conference (among rosters we have):** #{p[:name]}, #{p[:college][:name]} " \
               "(#{p[:overall]} OVR)#{coached_note}"
    end

    if conference[:all_americans].present?
      lines << "- ⭐ **All-Americans at this position:** #{conference[:all_americans].map { |aa| "#{aa[:name]} (#{aa[:college][:name]}, #{honor_label(aa)})" }.join(', ')}"
    end

    if conference[:nil_spend_leaderboard].present?
      lines << "- 💵 **NIL spend leaders:** #{nil_leaderboard_line(conference[:nil_spend_leaderboard])}"
    end

    lines << ""
    lines
  end

  def nil_leaderboard_line(leaderboard)
    leaderboard.first(5).map { |entry| "#{entry[:college][:name]} (#{currency(entry[:amount])})" }.join(", ")
  end

  def rating_leaderboard_line(leaderboard)
    leaderboard.first(5).map { |entry| "#{entry[:college][:name]} (#{entry[:average]})" }.join(", ")
  end

  def currency(amount)
    return "—" if amount.blank?

    ActiveSupport::NumberHelper.number_to_currency(amount, precision: 0)
  end
end
