# Renders the NsdBreakdownSerializer payload as Markdown for an LLM-based
# podcast generator (e.g. NotebookLM). It's a recruiting-decisions
# discussion — did each class answer the roster's needs — not a roster
# rating review (that's Roster Breakdown) and not a loss report (Portal
# Preview). See NsdBreakdownSerializer for how needs and quality are defined.
class NsdBreakdownMarkdownPresenter
  COVERAGE_LABELS = {
    "addressed" => "ADDRESSED", "patched" => "PATCHED", "ignored" => "IGNORED"
  }.freeze

  TYPE_LABELS = { "high_school" => "high school", "juco" => "JUCO", "transfer" => "portal transfer" }.freeze

  # The app never picks one of these — see VERDICT_RULES. Ordered best to
  # worst purely for reference in this file; nothing programmatic depends
  # on the order.
  VERDICT_TAGS = [
    "FULLY REPAIRED — the damage was fixed and then some, the class answered what the roster needed",
    "PATCHED UP — the big holes are covered, a few spots are held together with tape",
    "RUNNING ON A SPARE — drove off the lot, but there's a real problem nobody fixed",
    "LIMPED OUT OF THE PITS — the needs were obvious and the class mostly didn't meet them"
  ].freeze

  NSD_RULES = [
    "This episode is about HOW EACH TEAM RECRUITED, not how good the roster or the signees are. Ratings have " \
    "not progressed yet, so NEVER judge a position group's current strength or rating, and don't rate " \
    "individual signees as good or bad — signee quality is a later conversation. The only question is whether " \
    "the class filled the gaps: who walked out the door at a position versus who signed to replace them.",
    "Each position group lists what was lost, what signed, and a coverage grade: ADDRESSED (signed at least as " \
    "many players as the group needs), PATCHED (someone signed, but fewer than needed), IGNORED (a real need and " \
    "nobody signed at the position). A group's need is the starters it lost or the bodies it's short of its " \
    "depth target, whichever is larger. Groups with no need aren't graded. Talk about the actual players on " \
    "both sides, in the language of the example: 'they lost two starting linebackers and brought in one.'",
    "A signee fills a spot regardless of stars or overall — a solid 3 star replacing a departed starter is a " \
    "perfectly good answer, especially when a capable player is already on the roster. Stars, overalls and " \
    "national ranks are listed for color only; never invent one that isn't listed. Portal transfer overalls " \
    "are what he had at his previous school, before offseason progression.",
    "OVERSTOCKED means the team signed three or more players beyond the need at a group. That is not " \
    "automatically good — if the same team ignored other groups, call out the lopsided class.",
    "Compare each class to its conference using the national class ranking and conference standings when " \
    "they're given. A top-ranked class that ignored its biggest hole is a better story than the ranking alone.",
    "Spotlight each team's Splash Signing (the best-rated prospect) and Biggest NIL Investment as headlines, " \
    "and always name the Biggest Hole Left Open and the specific lost starters behind it.",
    "Use the scholarship and roster numbers to say what flexibility the coach has left: scholarships " \
    "remaining and roster room mean they can still add; none left means the class is what it is."
  ].freeze

  VERDICT_RULES = [
    "Close every team's segment with both hosts giving their own one-line pit-crew verdict, picked from: " \
    "#{VERDICT_TAGS.map { |t| t.split(' — ').first }.join(', ')} (worst). They don't have to agree — a split " \
    "verdict is good radio. Ground it in the evidence: how many needs were addressed, whether the biggest " \
    "hole got fixed, and how many spots went unfilled.",
    "Close the whole episode with the hosts ranking our teams' repair jobs from best to worst. Use the " \
    "closing section's repair scores as a data backstop, but argue with it if the eye test disagrees — a " \
    "need at a premium position like quarterback or left tackle can matter more than several filled depth spots. A team whose " \
    "class hasn't been logged yet has no score and shouldn't be ranked against the others."
  ].freeze

  def initialize(data)
    @data = data
  end

  def to_markdown
    lines = []
    lines.concat(PodcastShow.directive_lines(show_name: show_name))
    lines.concat(rule_lines("## ✍️ NATIONAL SIGNING DAY FORMAT (PRODUCER NOTE, DO NOT READ ALOUD)", NSD_RULES))
    lines.concat(rule_lines("## 🔧 VERDICT FORMAT (PRODUCER NOTE, DO NOT READ ALOUD)", VERDICT_RULES))
    lines.concat(PodcastShow.opening_script_lines(show_name: show_name, framing_hint: "how our rivals' recruiting classes shaped up on signing day"))
    lines.concat(PodcastShow.run_of_show_lines(segments))
    lines << "# ✍️ NATIONAL SIGNING DAY BREAKDOWN — #{show_name} — #{@data[:season][:year]}"
    lines << ""
    lines << "> #{producer_note}"
    lines << ""
    lines.concat(data_coverage_lines)

    @data[:teams].each { |team| lines.concat(team_section(team)) }
    lines.concat(repair_ranking_section)

    lines.join("\n")
  end

  private

  def show_name
    @data[:season][:dynasty]
  end

  def producer_note
    "PRODUCER NOTE: Signing-day review of our coached teams' recruiting. Each team's section covers its class " \
      "(size, stars, national and conference rank, NIL), then a position-by-position scorecard setting the " \
      "starters lost against the players signed, then the splash signing, the biggest hole left open, and the " \
      "scholarship math. This judges the recruiting decisions only — no talk of how strong any position group is."
  end

  def rule_lines(title, rules)
    lines = [ title, "" ]
    rules.each { |rule| lines << "- #{rule}" }
    lines << ""
    lines
  end

  def segments
    @data[:teams].map { |t| "#{t[:college][:name]} Signing Day" } + [ "Best and Worst Pit Crews: Ranking Our Teams" ]
  end

  def data_coverage_lines
    coverage = @data[:data_coverage]
    notes = []
    notes << "No signees logged yet for #{coverage[:teams_without_signees].join(', ')} — don't grade those classes." if coverage[:teams_without_signees].present?
    notes << "No portal data for #{coverage[:teams_without_portal_data].join(', ')} — losses are unknown there." if coverage[:teams_without_portal_data].present?
    notes << "#{coverage[:high_school_without_overall]} high school signee(s) have no overall entered; judge them by stars." if coverage[:high_school_without_overall].to_i.positive?
    notes << "#{coverage[:transfers_without_overall]} transfer(s) have no overall found; judge them by stars." if coverage[:transfers_without_overall].to_i.positive?
    return [] if notes.empty?

    [ "### ⚠️ DATA COVERAGE (PRODUCER NOTE, DO NOT READ ALOUD)", "", *notes.map { |n| "- #{n}" }, "" ]
  end

  def team_section(team)
    lines = [ "---", "", "## ✍️ #{team[:college][:name]} (Coach: #{team[:coach][:name]})" ]
    lines << "**Conference:** #{team[:college][:conference]}" if team[:college][:conference]
    lines << ""
    lines.concat(class_lines(team[:class_summary]))
    if team[:class_summary][:total_signed].zero?
      lines << "_Class not logged yet — no scorecard, so don't grade this team's recruiting._"
      lines << ""
    else
      lines.concat(scorecard_lines(team[:position_scorecard]))
      lines.concat(needs_lines(team[:needs_summary]))
      lines.concat(highlight_lines(team))
    end
    lines.concat(roster_math_lines(team[:roster_math]))
    lines
  end

  def class_lines(summary)
    lines = [ "### 📦 The Class", "" ]
    if summary[:total_signed].zero?
      return lines + [ "- No signees logged yet for this team.", "" ]
    end

    stars = summary[:star_counts].select { |_s, count| count.positive? }.sort.reverse.map { |s, count| "#{count} #{s}-star" }.join(", ")
    lines << "- #{summary[:total_signed]} signed: #{summary[:high_school]} high school, #{summary[:juco]} JUCO, " \
             "#{summary[:transfers]} portal transfers (#{stars.presence || 'no star ratings'}; average #{summary[:average_stars] || '—'} stars)"
    lines << "- NIL committed to this class: #{summary[:nil_committed]}"
    national = summary[:national]
    if national
      lines << "- National class ranking: ##{national[:ranking]} (#{national[:points]} points; #{national[:five_stars]} five-stars and #{national[:four_stars]} four-stars in the class)"
    end
    lines.concat(conference_lines(summary[:conference_comparison]))
    lines << ""
    lines
  end

  def conference_lines(comparison)
    return [] unless comparison

    standings = comparison[:standings].map { |c| "#{c[:college]} (##{c[:national_ranking]})#{c[:ours] ? ' ★ours' : ''}" }.join(", ")
    [ "- ##{comparison[:conference_rank]} of #{comparison[:teams_ranked]} in the #{comparison[:conference]} by class ranking. Top classes: #{standings}" ]
  end

  def scorecard_lines(groups)
    lines = [ "### 🧩 Position-by-Position Scorecard", "" ]
    shown = groups.select { |g| g[:coverage] || g[:signees].any? }
    return lines + [ "- No position group had a need and nobody signed.", "" ] if shown.empty?

    shown.each { |group| lines.concat(group_lines(group)) }
    lines << ""
    lines
  end

  def group_lines(group)
    grade = group[:coverage] ? COVERAGE_LABELS[group[:coverage]] : "NO NEED"
    flag = group[:overstocked] ? " [OVERSTOCKED]" : ""
    lines = [ "- **#{group[:position_group]}** — #{grade}#{flag}" ]
    lines << "  - Need: #{group[:need]} spot#{group[:need] == 1 ? '' : 's'} to fill, #{group[:signees].size} signed" if group[:need].positive?
    lines << "  - Lost starters: #{player_list(group[:starters_lost]) || 'none'}"
    other_lost = group[:lost].size - group[:starters_lost].size
    lines << "  - Also leaving: #{other_lost} reserve#{other_lost == 1 ? '' : 's'}; #{group[:remaining_depth]} left against a depth target of #{group[:min_healthy_depth]}" if group[:lost].any?
    lines << "  - Signed: #{group[:signees].map { |s| signee_text(s) }.join('; ').presence || 'nobody'}"
    lines
  end

  def player_list(players)
    return nil if players.blank?

    players.map { |p| "#{p[:name]} (#{p[:position]}, #{p[:overall]} OVR, #{p[:status].to_s.tr('_', ' ')})" }.join(", ")
  end

  def signee_text(signee)
    parts = [ signee[:position], TYPE_LABELS.fetch(signee[:type], signee[:type]) ]
    parts << "#{signee[:star_rating]}-star" if signee[:star_rating]
    parts << "#{signee[:overall]} OVR #{signee[:overall_source]}" if signee[:overall]
    parts << "national rank ##{signee[:national_rank]}" if signee[:national_rank]
    "#{signee[:name]} (#{parts.join(', ')})"
  end

  def needs_lines(summary)
    return [] if summary[:groups_with_needs].zero?

    score = summary[:repair_score] ? " Repair score: #{summary[:repair_score]}/100." : ""
    [ "### 🔧 Needs Addressed", "",
      "- #{summary[:addressed]} of #{summary[:groups_with_needs]} position groups with a need were addressed " \
      "(#{summary[:patched]} patched, #{summary[:ignored]} ignored).#{score}", "" ]
  end

  def highlight_lines(team)
    lines = [ "### ⭐ Highlights", "" ]
    splash = team[:splash_signing]
    if splash
      lines << "- Splash signing: #{signee_brief(splash[:best_signee])}"
      lines << "- Biggest NIL investment: #{signee_brief(splash[:biggest_nil_investment])}" if splash[:biggest_nil_investment]
    end
    hole = team[:biggest_hole]
    if hole
      lost = hole[:starters_lost].map { |p| p[:name] }.join(", ").presence || "depth shortfall"
      lines << "- Biggest hole left open: #{hole[:position_group]} (#{COVERAGE_LABELS[hole[:coverage]]}) — lost #{lost}; #{hole[:remaining_depth]} on hand vs. a target of #{hole[:min_healthy_depth]}"
    else
      lines << "- No open holes: every position group with a need was addressed." if team[:needs_summary][:groups_with_needs].positive?
    end
    lines << ""
    lines
  end

  def signee_brief(signee)
    parts = [ signee[:position], TYPE_LABELS.fetch(signee[:type], signee[:type]) ]
    parts << "#{signee[:star_rating]}-star" if signee[:star_rating]
    parts << "#{signee[:overall]} OVR" if signee[:overall]
    parts << "NIL #{signee[:nil_amount]}" if signee[:nil_amount].to_i.positive?
    "#{signee[:name]} (#{parts.join(', ')})"
  end

  def roster_math_lines(math)
    lines = [ "### 📋 What's Left", "",
              "- Scholarships: #{math[:scholarships_used]} used, #{math[:scholarships_remaining]} remaining (of #{math[:max_scholarships]}, recruits and transfers combined)",
              "- Roster: projects to #{math[:projected_roster_with_signees_so_far]} of #{math[:max_roster_size]} — #{roster_room_line(math)}", "" ]
    lines
  end

  def roster_room_line(math)
    room = math[:roster_room_before_cuts_needed]
    if room.positive?
      "#{room} spot#{room == 1 ? '' : 's'} of room before any cuts"
    elsif room.zero?
      "right at the cap"
    else
      "#{-room} over the cap, so cuts are coming"
    end
  end

  def repair_ranking_section
    ranking = @data[:repair_ranking]
    lines = [ "---", "", "## 🔧 BEST AND WORST PIT CREWS", "" ]
    return lines + [ "- No ranking available.", "" ] if ranking.blank?

    lines << "Ranked by repair score — how fully each class answered its roster needs, weighted by the size " \
             "of each need (addressed counts full, patched half, ignored zero). A data backstop for " \
             "the hosts, not the final word. Teams with no signees logged have no score."
    lines << ""
    ranking.each_with_index { |t, i| lines << ranking_line(t, i) }
    lines << ""
    lines
  end

  def ranking_line(entry, index)
    rank = entry[:class_ranking] ? ", ##{entry[:class_ranking]} class nationally" : ""
    return "#{index + 1}. #{entry[:college][:name]} — no score (class not logged)" unless entry[:repair_score]

    "#{index + 1}. #{entry[:college][:name]} — #{entry[:repair_score]}/100 repair score " \
      "(#{entry[:addressed]} of #{entry[:groups_with_needs]} needs addressed#{rank})"
  end
end
