# Renders the PortalPreviewSerializer payload as Markdown, meant for
# feeding into an LLM-based podcast generator (e.g. NotebookLM) rather than
# JSON. Unlike the report-card shows, this isn't a grading or betting
# format — it's a roster-planning discussion. Every Transfer, Pro Draft, or
# Graduation player is treated as gone (see PortalPreviewSerializer).
class PortalPreviewMarkdownPresenter
  STATUS_LABELS = {
    "transfer" => "Transfer", "pro_draft" => "Pro Draft", "graduation" => "Graduation", "staying" => "Staying"
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
    "Every player listed under Graduating Seniors, Declaring for the NFL Draft Early, or Transferring Out is " \
    "gone. Don't speculate about anyone coming back; talk about the loss and how to replace it.",
    "Decided to Stay lists players who thought about leaving but chose to stay. They are NOT losses and don't " \
    "count against the roster. Give it a quick beat of relief ('the one that almost got away') for the notable " \
    "names, especially a starter or a high overall, then move on.",
    "Each transfer shows the reason he gave in parentheses (Playing Time, Playing Style, Brand Exposure, Pro " \
    "Potential, Champ Contender, Conference Prestige, and so on). Work it in as a quick aside for the notable " \
    "ones — 'he wants more playing time', 'chasing a title contender' — one short phrase, not a whole " \
    "discussion. If several players on one team left for the same reason, that pattern is worth a single " \
    "line (e.g. a lot of Playing Time departures means a crowded depth chart).",
    "When flagging a position group that needs a starter or needs depth, name the specific player(s) responsible " \
    "for that hole, not just the position group in the abstract.",
    "A position flagged BELOW CONFERENCE AVERAGE is a different problem than one flagged STARTER LEAVING — a " \
    "below-average starter who isn't going anywhere is a place the coach should actively upgrade " \
    "through the portal or recruiting, not a hole in the lineup. Keep those two conversations distinct.",
    "Use the scholarship/roster numbers to say something concrete about how much freedom the coach actually has " \
    "— plenty of scholarships and roster room means they can be aggressive in the portal; short on either means " \
    "they have to be selective, or roster cuts are already coming regardless of who else leaves.",
    "A senior is gone via graduation either way; if he's also Pro Draft, that's a program flexing, worth " \
    "celebrating, not a hole to panic about. An underclassman declaring early is a real loss of remaining " \
    "eligibility."
  ].freeze

  VERDICT_RULES = [
    "Close every team's segment with both hosts giving their own one-line verdict tag for how bad the offseason " \
    "damage looks, picked from: #{VERDICT_TAGS.map { |t| t.split(' — ').first }.join(', ')} (worst). They don't " \
    "have to pick the same tag — a split verdict is good radio, not a problem to resolve. Ground it in the " \
    "evidence: how many departures, whether the damage is concentrated at one or two positions versus " \
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
    "PRODUCER NOTE: Roster-planning preview for our coached teams ahead of the transfer portal. Every player " \
      "listed is leaving, sorted into three groups: Graduating Seniors (a senior's career is over regardless of " \
      "the draft — plain graduation and a senior who's also Pro Draft are the same story, the latter just gets a " \
      "draft-round mention), Declaring for the NFL Draft Early (an underclassman Pro Draft entry — a real loss of " \
      "eligibility), and Transferring Out (in the portal, with the reason he gave). Decided to Stay lists close " \
      "calls — players who considered leaving but are staying — and is not counted as a loss. Position Needs covers two " \
      "separate questions: depth (current roster count minus everyone leaving, against a target headcount) " \
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

    lines.concat(departures_section("🎓 Graduating Seniors", team[:departures][:graduating_seniors]))
    lines.concat(departures_section("🏈 Declaring for the NFL Draft Early", team[:departures][:declaring_early]))
    lines.concat(departures_section("🔄 Transferring Out", team[:departures][:transferring]))
    lines.concat(departures_section("😅 Decided to Stay", team[:departures][:decided_to_stay]))
    lines.concat(most_important_section(team[:departures][:most_important]))
    lines.concat(position_needs_section(team[:position_needs]))
    lines.concat(roster_math_section(team[:roster_math]))

    lines
  end

  def summary_line(summary)
    return "—" unless summary

    "#{summary[:roster_size]} on the roster — #{summary[:graduating_seniors]} graduating seniors, " \
      "#{summary[:declaring_early]} declaring for the draft early, " \
      "#{summary[:transferring]} transferring out, #{summary[:staying]} staying " \
      "(#{summary[:decided_to_stay]} of them considered leaving but decided to stay)"
  end

  def departures_section(title, entries)
    lines = [ "### #{title}", "" ]
    return lines + [ "- None.", "" ] if entries.blank?

    entries.each { |e| lines << departure_line(e) }
    lines << ""
    lines
  end

  def departure_line(entry)
    status = STATUS_LABELS.fetch(entry[:status], entry[:status])
    detail = entry[:detail].present? ? " (#{entry[:detail]})" : ""
    unmatched_note = entry[:matched] ? "" : " [unmatched to a roster record — verify]"
    games_played = entry[:games_played].present? ? ", #{entry[:games_played]} GP" : ""
    "- #{entry[:name]} (#{entry[:position]}, #{entry[:class_year]}, #{entry[:overall]} OVR#{games_played}) — #{status}#{detail}#{unmatched_note}"
  end

  def most_important_section(entries)
    lines = [ "### ⭐ Most Important Losses", "" ]
    return lines + [ "- Nothing significant.", "" ] if entries.blank?

    entries.each { |e| lines << departure_line(e) }
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
      "#{need[:min_healthy_depth]}), #{need[:remaining_depth]} left once everyone leaving is gone"
  end

  def starter_flag_line(starter)
    flags = []
    flags << "STARTER LEAVING" if starter[:starter_leaving]
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
             "#{math[:projected_roster_with_signees_so_far]} once everyone leaving is gone and this cycle's signees are counted (#{math[:max_roster_size]} max) — #{roster_room_line(math)}"
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
             "transfers) — a data backstop for the hosts, not the final word. They should form their own ranking and " \
             "are free to argue with the order below."
    lines << ""
    ranking.each_with_index { |t, i| lines << severity_ranking_line(t, i) }
    lines << ""
    lines
  end

  def severity_ranking_line(entry, index)
    "#{index + 1}. #{entry[:college][:name]} — #{entry[:severity_score]} combined OVR at risk " \
      "(#{entry[:graduating_seniors]} graduating seniors, #{entry[:declaring_early]} declaring for the draft " \
      "early, #{entry[:transferring]} transferring out)"
  end
end
