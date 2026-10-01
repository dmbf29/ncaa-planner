# Renders the NsdBreakdownSerializer payload as Markdown for an LLM-based
# podcast generator (e.g. NotebookLM). Deliberately compact: one short block
# per team (high school, transfers, the class overall), then the hosts rank
# the classes. It's about recruiting numbers, not roster strength — that's
# Roster Breakdown's job, and ratings haven't progressed yet.
class NsdBreakdownMarkdownPresenter
  # The app never picks one of these — see VERDICT_RULES. Ordered weakest to
  # strongest purely for reference in this file; nothing programmatic depends
  # on the order.
  VERDICT_TAGS = [
    "EMPTY BAR — barely loaded the class, nothing here to build a lineup on",
    "WARM-UP SET — some weight on the bar, but nowhere near a real lift",
    "WORKING SET — a solid, honest class that does the job",
    "PERSONAL RECORD — a class that's the best lift this program has put up"
  ].freeze

  NSD_RULES = [
    "This episode is about HOW EACH TEAM RECRUITED — the numbers in the class — not how strong the roster is. " \
    "Ratings have not progressed yet, so never judge a position group's current strength. Overalls here are " \
    "what each signee brings in before offseason progression.",
    "Each team has four parts: High School Signees, Transfers, Players to Watch, and the Class Overall. Cover " \
    "them in that order, keep it moving, and don't read every number — pick the ones that tell the story.",
    "The comparisons are the point. High school signees are compared to the team's true freshmen from last " \
    "season; transfers are compared to the team's whole roster from last season; the class rank and spend are " \
    "compared to the rest of the conference. 'Last season' means the roster as it stands now.",
    "Players to Watch lists the best high school signee, the best transfer, and the best signee on offense and " \
    "on defense by overall (one player can fill more than one slot). Name them, and also the player the team " \
    "spent the most on. A high school signee is described by stars; a transfer by his class year. If a pick " \
    "says 'no overall entered', don't quote an overall.",
    "Roster Depth Worries are position groups that will be short on bodies on the roster once departures and " \
    "this class are counted; the number is how many players the roster will have there. If none are listed, " \
    "say the team's depth is covered.",
    "Average overall is the whole class, high school and transfers together, as they arrive before offseason " \
    "progression.",
    "A comparison marked as unavailable (for example last year's class) is simply not discussed.",
    "The SIGNING REFERENCE LIST at the very end is background only: use it to name-drop another signee when it " \
    "helps a point, never to read through names. Only quote what's listed for a player; never invent a rating."
  ].freeze

  VERDICT_RULES = [
    "Close the whole episode with a real debate: the hosts rank our teams' classes from worst to best and each " \
    "gives every team a one-line strength tag picked from: " \
    "#{VERDICT_TAGS.map { |t| t.split(' — ').first }.join(', ')} (strongest). They don't have to agree on the " \
    "order or a tag — a split verdict is good radio.",
    "The closing section lists the teams' numbers side by side in no particular order. Nobody has handed the " \
    "hosts a ranking; they argue it out from the evidence. Real arguments to make: a top national rank " \
    "versus a poor value for the money spent, big overalls versus a thin or lopsided class, transfers " \
    "propping up a weak high school group, and roster depth worries. Each host should defend a position and " \
    "concede a point.",
    "Dollars per overall point is the value-for-money number: NIL dollars spent divided by the total overall " \
    "points the class brought in, so LOWER is better value. Use it to question a big spender or praise a bargain."
  ].freeze

  def initialize(data)
    @data = data
  end

  def to_markdown
    lines = []
    lines.concat(PodcastShow.directive_lines(show_name: show_name))
    lines.concat(rule_lines("## ✍️ NATIONAL SIGNING DAY FORMAT (PRODUCER NOTE, DO NOT READ ALOUD)", NSD_RULES))
    lines.concat(rule_lines("## 💪 VERDICT FORMAT (PRODUCER NOTE, DO NOT READ ALOUD)", VERDICT_RULES))
    lines.concat(PodcastShow.opening_script_lines(show_name: show_name, framing_hint: "how our rivals' recruiting classes shaped up on signing day"))
    lines.concat(PodcastShow.run_of_show_lines(segments))
    lines << "# ✍️ NATIONAL SIGNING DAY BREAKDOWN — #{show_name} — #{@data[:season][:year]}"
    lines << ""
    lines.concat(data_coverage_lines)
    @data[:teams].each { |team| lines.concat(team_section(team)) }
    lines.concat(ranking_section)
    lines.concat(reference_section)
    lines.join("\n")
  end

  private

  def show_name
    @data[:season][:dynasty]
  end

  def rule_lines(title, rules)
    [ title, "", *rules.map { |rule| "- #{rule}" }, "" ]
  end

  def segments
    @data[:teams].map { |t| "#{t[:college][:name]} Signing Day" } + [ "Ranking Our Teams' Classes: Worst to Best" ]
  end

  def data_coverage_lines
    coverage = @data[:data_coverage]
    notes = []
    notes << "No signees logged for #{coverage[:teams_without_signees].join(', ')} — skip those classes." if coverage[:teams_without_signees].present?
    notes << "No portal data for #{coverage[:teams_without_portal_data].join(', ')} — their roster depth worries can't be trusted." if coverage[:teams_without_portal_data].present?
    notes << "No class ranking for #{coverage[:teams_without_class_ranking].join(', ')}." if coverage[:teams_without_class_ranking].present?
    notes << "#{coverage[:high_school_without_overall]} high school signee(s) have no overall entered." if coverage[:high_school_without_overall].to_i.positive?
    notes << "#{coverage[:transfers_without_overall]} transfer(s) have no overall found." if coverage[:transfers_without_overall].to_i.positive?
    return [] if notes.empty?

    [ "### ⚠️ DATA COVERAGE (PRODUCER NOTE, DO NOT READ ALOUD)", "", *notes.map { |n| "- #{n}" }, "" ]
  end

  def team_section(team)
    lines = [ "---", "", "## ✍️ #{team[:college][:name]} (Coach: #{team[:coach][:name]})" ]
    lines << "**Conference:** #{team[:college][:conference]}" if team[:college][:conference]
    lines << ""
    return lines + [ "- No signees logged yet.", "" ] if team[:total_signed].zero?

    lines.concat(high_school_lines(team))
    lines.concat(transfer_lines(team))
    lines.concat(watch_lines(team[:players_to_watch]))
    lines.concat(overall_lines(team))
    lines
  end

  def high_school_lines(team)
    hs = team[:high_school]
    lines = [ "### 🎓 High School Signees", "" ]
    return lines + [ "- None signed.", "" ] if hs[:signed].zero?

    lines << "- #{hs[:signed]} signed: #{star_text(hs[:star_counts])}"
    lines << average_line("Average overall", hs[:average_overall], hs[:overalls_entered], hs[:signed])
    if hs[:last_season_freshman_average]
      lines << "- Last season's true freshmen averaged #{hs[:last_season_freshman_average]} (#{hs[:last_season_freshman_count]} players)" \
               "#{comparison_text(hs[:difference_vs_freshmen], 'this class', plural: false)}"
    end
    lines << "- Also signed #{team[:juco_signed]} JUCO player#{team[:juco_signed] == 1 ? '' : 's'} (not counted above)." if team[:juco_signed].positive?
    lines << ""
    lines
  end

  def transfer_lines(team)
    tr = team[:transfers]
    lines = [ "### 🔄 Transfers", "" ]
    return lines + [ "- None signed.", "" ] if tr[:signed].zero?

    lines << "- #{tr[:signed]} transfers signed"
    lines << average_line("Average overall", tr[:average_overall], tr[:overalls_found], tr[:signed])
    if tr[:last_season_team_average]
      lines << "- The whole roster averaged #{tr[:last_season_team_average]} last season#{comparison_text(tr[:difference_vs_team], 'the transfers')}"
    end
    lines << ""
    lines
  end

  def overall_lines(team)
    overall = team[:overall]
    lines = [ "### 📊 Class Overall", "" ]
    lines << "- #{team[:total_signed]} total signees (#{team[:high_school][:signed]} high school, #{team[:transfers][:signed]} transfers)"
    lines << average_line("Average overall of the whole class", overall[:average_overall], overall[:value][:signees_counted], team[:total_signed])
    lines << ranking_line(overall)
    lines.concat(spend_lines(overall[:spend], overall[:biggest_spend]))
    lines << value_line(overall)
    lines << worry_line(overall[:positions_of_worry])
    lines << ""
    lines
  end

  def ranking_line(overall)
    return "- National class ranking: not available" unless overall[:national_ranking]

    comparison = overall[:ranking_vs_conference]
    text = "- National class ranking: ##{overall[:national_ranking]}"
    if comparison
      best = comparison[:best_in_conference]
      text += " — #{ordinal(comparison[:conference_rank])} of #{comparison[:teams_ranked]} in the #{comparison[:conference]}" \
              " (best class in the conference: #{best[:college]}, ##{best[:national_ranking]})"
    end
    text += "; last year's class was ranked ##{overall[:last_year_ranking]}" if overall[:last_year_ranking]
    text
  end

  def spend_lines(spend, biggest)
    text = "- NIL spent on the class: #{currency(spend[:nil_spent])}"
    if spend[:conference_rank]
      text += " — ranks #{ordinal(spend[:conference_rank])} of #{spend[:conference_teams_compared]} in the conference for spend (conference average #{currency(spend[:conference_average])})"
    end
    text += "; last year they spent #{currency(spend[:last_year])}" if spend[:last_year]
    lines = [ text ]
    lines << "- Biggest spend on one player: #{player_text(biggest)} — #{currency(biggest[:nil_dollars])} in NIL" if biggest
    lines
  end

  def value_line(overall)
    value = overall[:value]
    return "- Value for money: not available (no overalls on file)" unless value[:dollars_per_overall_point]

    "- Value for money: #{currency(value[:dollars_per_overall_point])} per overall point (#{currency(overall[:spend][:nil_spent])} " \
      "for #{value[:overall_points]} overall points; lower is better value)"
  end

  def worry_line(worries)
    return "- Roster depth worries: none — every position group has enough players" if worries.empty?

    list = worries.map { |w| "#{w[:position_group]} (only #{w[:projected_depth]} on the roster)" }.join(", ")
    "- Roster depth worries: #{list}"
  end

  def star_text(star_counts)
    parts = star_counts.select { |_stars, count| count.positive? }.sort.reverse.map { |stars, count| "#{count} #{stars}-star" }
    parts.empty? ? "no star ratings" : parts.join(", ")
  end

  def average_line(label, average, counted, total)
    return "- #{label}: not available (no overalls on file)" unless average

    partial = counted < total ? " (from #{counted} of #{total} with an overall)" : ""
    "- #{label}: #{average}#{partial}"
  end

  def comparison_text(difference, subject, plural: true)
    return "" if difference.nil?
    return " — #{subject} #{plural ? 'are' : 'is'} right in line" if difference.zero?

    verb = difference.positive? ? "beat" : "trail"
    " — #{subject} #{plural ? verb : "#{verb}s"} that by #{difference.abs}"
  end

  LABELS = {
    high_school: "Top high school signee", transfer: "Top transfer",
    offense: "Top offensive signee", defense: "Top defensive signee"
  }.freeze

  # One line per player: a signee who is the pick for several slots appears
  # once with every label he earned, rather than being repeated.
  def watch_lines(picks)
    lines = [ "### 👀 Players to Watch", "" ]
    grouped = picks.select { |_slot, player| player }.group_by { |_slot, player| player[:name] }
    return lines + [ "- No standouts to name yet.", "" ] if grouped.empty?

    grouped.each_value do |entries|
      player = entries.first.last
      labels = entries.map { |slot, _| LABELS[slot] }.join(" / ")
      lines << "- #{labels}: #{player_text(player)}#{player[:basis] == 'stars' ? ' — no overall entered, best-rated by stars' : ''}"
    end
    lines << ""
    lines
  end

  # A high school/JUCO signee reads as his stars, a transfer as his class
  # year (his stars say little about a player already on a roster).
  def descriptor(player)
    player[:type] == "transfer" ? player[:class_year] : ("#{player[:star_rating]}-star" if player[:star_rating])
  end

  def player_text(player)
    detail = [ player[:position], descriptor(player), ("#{player[:overall]} OVR" if player[:overall]), origin(player) ].compact.join(", ")
    "#{player[:name]} (#{detail})"
  end

  # Where a transfer came from, when his previous roster is known.
  def origin(player)
    "from #{player[:from_college]}" if player[:type] == "transfer" && player[:from_college]
  end

  def currency(amount)
    return "—" if amount.nil?

    ActiveSupport::NumberHelper.number_to_currency(amount, precision: 0)
  end

  def ordinal(number)
    return "#{number}th" if (11..13).cover?(number % 100)

    suffix = { 1 => "st", 2 => "nd", 3 => "rd" }.fetch(number % 10, "th")
    "#{number}#{suffix}"
  end

  def reference_section
    lines = [ "---", "", "## 📇 SIGNING REFERENCE LIST (BACKGROUND ONLY, DO NOT READ ALOUD)", "" ]
    @data[:teams].each do |team|
      next if team[:signees].empty?

      lines << "### #{team[:college][:name]}"
      team[:signees].group_by { |s| s[:type] == "transfer" ? "Transfers" : "High School/JUCO" }.each do |label, signees|
        lines << "**#{label}**"
        signees.each { |s| lines << "- #{reference_line(s)}" }
      end
      lines << ""
    end
    lines
  end

  def reference_line(signee)
    parts = [ signee[:position], descriptor(signee), ("#{signee[:overall]} OVR" if signee[:overall]), origin(signee),
              ("national rank ##{signee[:national_rank]}" if signee[:national_rank]), ("NIL #{currency(signee[:nil_dollars])}" if signee[:nil_dollars].to_i.positive?) ]
    "#{signee[:name]} — #{parts.compact.join(', ')}"
  end

  def ranking_section
    lines = [ "---", "", "## 💪 RANKING THE CLASSES: WORST TO BEST", "" ]
    lines << "Our teams side by side, in alphabetical order. This is NOT a ranking — the hosts debate and decide it."
    lines << ""
    @data[:class_comparison].each { |t| lines.concat(comparison_lines(t)) }
    lines
  end

  def comparison_lines(entry)
    rank = entry[:national_ranking] ? "##{entry[:national_ranking]} nationally" : "unranked"
    rank += " (#{ordinal(entry[:conference_rank])} in the conference)" if entry[:conference_rank]
    worries = entry[:positions_of_worry].presence&.join(", ") || "none"
    [ "- **#{entry[:college][:name]}**: class rank #{rank}; #{entry[:total_signed]} signees " \
      "(#{entry[:high_school_signed]} high school, #{entry[:transfers_signed]} transfers); average overall " \
      "#{entry[:average_overall] || '—'}; #{currency(entry[:nil_spent])} NIL spent; " \
      "#{entry[:dollars_per_overall_point] ? "#{currency(entry[:dollars_per_overall_point])} per overall point" : 'value not available'}; " \
      "roster depth worries: #{worries}", "" ]
  end
end
