# Renders the PortalPreviewSerializer payload as Markdown, meant for
# feeding into an LLM-based podcast generator (e.g. NotebookLM) rather than
# JSON. Unlike the report-card shows, this isn't a grading or betting
# format — it's a roster-planning discussion, so the rules below focus on
# keeping "confirmed gone" and "already in the portal but could still come
# back" clearly distinct — a Transfer/Pro Draft status always means the
# player has already left, never that they're still deciding whether to.
class PortalPreviewMarkdownPresenter
  STATUS_LABELS = { "transfer" => "Transfer", "pro_draft" => "Pro Draft", "graduation" => "Graduation" }.freeze

  PERSUASION_LABELS = {
    "not_applicable" => "—", "none" => "None", "extremely_low" => "Extremely Low", "very_low" => "Very Low",
    "low" => "Low", "medium" => "Medium", "high" => "High", "very_high" => "Very High",
    "extremely_high" => "Extremely High", "guaranteed" => "Guaranteed"
  }.freeze

  # The app never picks one of these — see VERDICT_RULES. Ordered least to
  # most severe purely for reference in this file; nothing programmatic
  # depends on the order.
  VERDICT_TAGS = [
    "SMOOTH SAILING — barely any damage, the roster is basically intact",
    "MINOR LEAK — lost some depth, nothing that sinks the season",
    "TAKING ON WATER — real losses at real positions, there's genuine work to do",
    "SINKING SHIP — the roster took a beating and it shows"
  ].freeze

  PORTAL_RULES = [
    "Every player under Transfer or Pro Draft has ALREADY entered the portal/declared — there's no 'talk them " \
    "out of leaving' moment left to have. Persuasion chance is the odds of getting them to RETURN to campus, " \
    "not the odds of having kept them in the first place. Frame it that way: 'is there a shot he comes back,' " \
    "never 'can we keep him from leaving.'",
    "Keep 'confirmed gone' and 'could still come back' clearly distinct. A confirmed departure (graduating, or " \
    "already out with no realistic path back) is settled — talk about the loss and how to replace it. A player " \
    "in the portal with a genuine uncertain return is a live situation — talk about the odds of getting him " \
    "back and what's driving the decision.",
    "Treat persuasion chance as a real lever the coach can still pull on an already-departed player, not just a " \
    "number — connect it to the reason shown (Playing Time, Playing Style, Brand Exposure, Pro Potential, Champ " \
    "Contender) when discussing what it would actually take to bring him back.",
    "When flagging a position group that needs a starter or needs depth, name the specific player(s) responsible " \
    "for that hole, not just the position group in the abstract.",
    "A position flagged BELOW CONFERENCE AVERAGE is a different problem than one flagged STARTER LEAVING/STARTER " \
    "IN THE PORTAL — a below-average starter who isn't going anywhere is a place the coach should actively upgrade " \
    "through the portal or recruiting, not a hole in the lineup. Keep those two conversations distinct.",
    "Use the scholarship/roster numbers to say something concrete about how much freedom the coach actually has " \
    "— plenty of scholarships and roster room means they can be aggressive in the portal; short on either means " \
    "they have to be selective, or roster cuts are already coming regardless of who else leaves.",
    "A player tagged 'Probably Coming Home' has genuinely entered the portal — don't flatten that into a " \
    "settled certainty. Play it a little mysterious: 'campus buzz says he's exploring his options, but the " \
    "smart money says he ends up back' beats just declaring him staying. Keep it brief either way — this is a " \
    "lighter beat, not a real threat, and he's not confirmed anything until he's actually back on the roster.",
    "Graduating Seniors and Declaring for the NFL Draft Early are BOTH settled, not live storylines — the " \
    "difference between them is eligibility, not certainty. A senior is gone via graduation either way; if he's " \
    "also Pro Draft, that's a program flexing, worth celebrating, not a hole to panic about. An underclassman " \
    "declaring early is a real loss of remaining eligibility — talk about replacing him, not persuading him " \
    "back, since this group has no realistic path to staying."
  ].freeze

  VERDICT_RULES = [
    "Close every team's segment with both hosts giving their own one-line verdict tag for how bad the offseason " \
    "damage looks, picked from: #{VERDICT_TAGS.map { |t| t.split(' — ').first }.join(', ')} (worst). They don't " \
    "have to pick the same tag — a split verdict is good radio, not a problem to resolve. Ground it in the " \
    "evidence: how many confirmed departures, whether the damage is concentrated at one or two positions versus " \
    "spread thin, and whether the roster math gives the coach room to fix it or leaves them boxed in.",
    "Close the whole episode with the hosts ranking our own coached teams from most damage taken to least. Use " \
    "the combined-overall ranking in the closing section as a data backstop, but they should argue with it if " \
    "the eye test disagrees — losing one star player at a premium position can feel worse than losing several " \
    "role players whose overalls add up to more."
  ].freeze

  def initialize(data)
    @data = data
  end

  def to_markdown
    lines = []
    lines.concat(PodcastShow.directive_lines(show_name: show_name))
    lines.concat(portal_format_lines)
    lines.concat(verdict_format_lines)
    lines.concat(PodcastShow.opening_script_lines(show_name: show_name, framing_hint: "our roster picture right before the transfer portal opens"))
    lines.concat(PodcastShow.run_of_show_lines(segments))
    lines << "# 🚪 PORTAL PREVIEW — #{show_name} — #{@data[:season][:year]}"
    lines << ""
    lines << "> #{producer_note}"
    lines << ""

    @data[:teams].each { |team| lines.concat(team_section(team)) }

    lines.concat(severity_ranking_section)

    lines.join("\n")
  end

  private

  def show_name
    @data[:season][:dynasty]
  end

  def producer_note
    "PRODUCER NOTE: Roster-planning preview for our coached teams ahead of the transfer portal. A Transfer/Pro " \
      "Draft status means that player has ALREADY entered the portal or declared — persuasion chance below is " \
      "the odds of getting him back to campus, not the odds of having kept him from leaving. Every departure is " \
      "sorted into four groups: Graduating Seniors (a senior's career is over regardless of the draft — plain " \
      "graduation and a senior who's also Pro Draft are the same story, the latter just gets a draft-round " \
      "mention), Declaring for the NFL Draft Early (an underclassman Pro Draft entry with no realistic path " \
      "back — a real loss of eligibility, not a program success), In the Portal: Slim Chance of a Return (a " \
      "genuine, if long-shot, uncertain return), and In the Portal, Probably Coming Home (the numbers lean " \
      "toward him returning — worth a brief, mysterious mention, not a real threat). Position Needs covers two " \
      "separate questions: depth (current roster count minus everyone likely gone — graduating seniors, early " \
      "draft declarations, AND slim-chance-of-returning portal players, against a target headcount; a " \
      "below-medium persuasion chance rarely actually converts, so it's planned around as a loss, not a maybe) " \
      "and starter quality (our starter at each individual position — not a blended group — against the " \
      "conference-wide average starter at that same position, regardless of whether that player is leaving)."
  end

  def portal_format_lines
    lines = [ "## 🚪 PORTAL PREVIEW FORMAT (PRODUCER NOTE, DO NOT READ ALOUD)", "" ]
    PORTAL_RULES.each { |rule| lines << "- #{rule}" }
    lines << ""
    lines
  end

  def verdict_format_lines
    lines = [ "## ⚓ VERDICT FORMAT (PRODUCER NOTE, DO NOT READ ALOUD)", "" ]
    VERDICT_RULES.each { |rule| lines << "- #{rule}" }
    lines << ""
    lines
  end

  def segments
    @data[:teams].map { |t| "#{t[:college][:name]} Portal Preview" } + [ "Who Got Hit Hardest: Ranking Our Teams" ]
  end

  def team_section(team)
    lines = []
    lines << "---"
    lines << ""
    lines << "## 🚪 #{team[:college][:name]} (Coach: #{team[:coach][:name]})"
    lines << "**Conference:** #{team[:college][:conference]}" if team[:college][:conference]
    lines << "**Roster Snapshot:** #{summary_line(team[:summary])}"
    lines << ""

    lines.concat(departures_section("🎓 Graduating Seniors", team[:departures][:graduating_seniors], show_persuasion: false))
    lines.concat(departures_section("🏈 Declaring for the NFL Draft Early", team[:departures][:declaring_early], show_persuasion: false))
    lines.concat(departures_section("🔄 In the Portal: Slim Chance of a Return", team[:departures][:slim_chance_of_return], show_persuasion: true))
    lines.concat(departures_section("↩️ In the Portal, Probably Coming Home", team[:departures][:likely_return], show_persuasion: true))
    lines.concat(most_important_section(team[:departures][:most_important]))
    lines.concat(position_needs_section(team[:position_needs]))
    lines.concat(roster_math_section(team[:roster_math]))

    lines
  end

  def summary_line(summary)
    return "—" unless summary

    "#{summary[:roster_size]} on the roster — #{summary[:graduating_seniors]} graduating seniors, " \
      "#{summary[:declaring_early]} declaring for the draft early, " \
      "#{summary[:slim_chance_of_return]} in the portal with a slim chance of returning, " \
      "#{summary[:likely_return]} in the portal but probably coming home, #{summary[:likely_staying]} presumed staying"
  end

  def departures_section(title, entries, show_persuasion:)
    lines = [ "### #{title}", "" ]
    return lines + [ "- None.", "" ] if entries.blank?

    entries.each { |e| lines << departure_line(e, show_persuasion: show_persuasion) }
    lines << ""
    lines
  end

  def departure_line(entry, show_persuasion:)
    status = STATUS_LABELS.fetch(entry[:status], entry[:status])
    detail = entry[:detail].present? ? " (#{entry[:detail]})" : ""
    persuasion = show_persuasion ? " — persuasion chance: #{PERSUASION_LABELS.fetch(entry[:persuasion_chance], entry[:persuasion_chance])}" : ""
    unmatched_note = entry[:matched] ? "" : " [unmatched to a roster record — verify]"
    "- #{entry[:name]} (#{entry[:position]}, #{entry[:class_year]}, #{entry[:overall]} OVR) — #{status}#{detail}#{persuasion}#{unmatched_note}"
  end

  def most_important_section(entries)
    lines = [ "### ⭐ Most Important Losses", "" ]
    return lines + [ "- Nothing significant.", "" ] if entries.blank?

    entries.each { |e| lines << departure_line(e, show_persuasion: e[:risk_tier] == "uncertain_return") }
    lines << ""
    lines
  end

  def position_needs_section(needs)
    lines = [ "### 🧩 Position Needs", "" ]
    return lines if needs.blank?

    flagged_groups = needs.select { |n| n[:needs_depth] || flagged_starters(n).any? }
    if flagged_groups.blank?
      lines << "- No position group is flagged — depth and starter quality both look fine across the board."
      lines << ""
      return lines
    end

    flagged_groups.each { |n| lines.concat(position_need_lines(n)) }
    lines << ""
    lines
  end

  def flagged_starters(need)
    need[:starters].select { |s| s[:below_average] || s[:starter_leaving] }
  end

  def position_need_lines(need)
    lines = [ position_group_header_line(need) ]
    flagged_starters(need).each { |s| lines << starter_flag_line(s) }
    lines
  end

  def position_group_header_line(need)
    flag = need[:needs_depth] ? " [NEEDS DEPTH]" : ""
    "- **#{need[:position_group]}**#{flag} — #{need[:current_depth]} on hand now (bare minimum target " \
      "#{need[:min_healthy_depth]}), #{need[:remaining_depth]} left once everyone likely gone (graduating " \
      "seniors, early draft declarations, and portal players with a slim chance of returning) actually leaves"
  end

  def starter_flag_line(starter)
    flags = []
    case starter[:starter][:risk_tier]
    when "confirmed" then flags << "STARTER LEAVING"
    when "uncertain_return" then flags << "STARTER IN THE PORTAL"
    end
    flags << "BELOW CONFERENCE AVERAGE" if starter[:below_average]

    player = starter[:starter]
    avg_note = starter[:conference_avg_starter_overall] ? \
      " vs. conference average #{starter[:conference_avg_starter_overall]} OVR (#{starter[:conference_sample_size]} teams)" : ""
    "  - #{starter[:position]}: #{player[:name]} (#{player[:overall]} OVR#{avg_note}) [#{flags.join(', ')}]"
  end

  def roster_math_section(math)
    lines = [ "### 📋 Work To Do", "" ]
    return lines if math.blank?

    lines << "- Scholarships: #{math[:scholarships_used]} used, #{math[:scholarships_remaining]} remaining " \
             "(of #{math[:max_scholarships]}, recruits and portal transfers signed this cycle combined)"
    lines << "- Roster: #{math[:current_roster_size]} on hand now, projects to " \
             "#{math[:projected_roster_with_signees_so_far]} once everyone likely gone (graduating seniors, " \
             "early draft declarations, and portal players with a slim chance of returning) leaves and this " \
             "cycle's signees are counted (#{math[:max_roster_size]} max) — #{roster_room_line(math)}"
    lines << ""
    lines
  end

  def roster_room_line(math)
    room = math[:roster_room_before_cuts_needed]
    if room.positive?
      "#{room} spot#{room == 1 ? '' : 's'} of room before any cuts would be needed"
    elsif room.zero?
      "right at the cap, no room left without a cut"
    else
      "already #{-room} over the cap — cuts are coming before the season regardless of who else leaves"
    end
  end

  def severity_ranking_section
    ranking = @data[:severity_ranking]
    lines = [ "---", "", "## ⚓ WHO GOT HIT HARDEST", "" ]
    return lines + [ "- No ranking available.", "" ] if ranking.blank?

    lines << "Ranked by total overall walking out the door (graduating seniors, early draft declarations, and " \
             "in-the-portal players with a slim-but-real chance of returning — not the ones probably coming " \
             "home) — a data backstop for the hosts, not the final word. They should form their own ranking and " \
             "are free to argue with the order below."
    lines << ""
    ranking.each_with_index { |t, i| lines << severity_ranking_line(t, i) }
    lines << ""
    lines
  end

  def severity_ranking_line(entry, index)
    "#{index + 1}. #{entry[:college][:name]} — #{entry[:severity_score]} combined OVR at risk " \
      "(#{entry[:graduating_seniors]} graduating seniors, #{entry[:declaring_early]} declaring for the draft " \
      "early, #{entry[:slim_chance_of_return]} in the portal with a slim chance of returning)"
  end
end
