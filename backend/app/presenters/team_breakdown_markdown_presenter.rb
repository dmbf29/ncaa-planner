# Renders the TeamBreakdownSerializer payload as Markdown, meant for feeding
# into an LLM-based podcast generator (e.g. NotebookLM) rather than JSON.
# Shape of the episode: a "where each team stands" opening, one short segment
# per position room, then a closing where the hosts debate their verdicts.
# It covers the roster after offseason progression only — recruiting classes
# belong to the signing day episode and departures to Portal Preview.
class TeamBreakdownMarkdownPresenter
  # The app never picks one of these — see VERDICT_RULES. Ordered weakest to
  # strongest purely for reference in this file; nothing programmatic depends
  # on the order.
  VERDICT_TAGS = [
    "UNDER CONSTRUCTION — too many rooms are still a work in progress",
    "MOVE-IN READY — livable and sturdy, with a few rooms still to furnish",
    "FULLY FURNISHED — strong rooms nearly everywhere, nothing major missing",
    "PENTHOUSE — the best roster in the building, top-shelf from top to bottom"
  ].freeze

  ROSTER_RULES = [
    "It's the end of April, right after spring practice, and the new season is still ahead (see the broadcast " \
    "date and year at the top). This is the roster AFTER the offseason's progression. It is not a recruiting or portal episode: don't " \
    "discuss recruiting classes or who left (other shows cover those), only the roster as it stands now.",
    "Each room is judged on its STARTERS (quarterback 1, running backs 2, receivers 3, tight end 1, offensive " \
    "line 5, defensive line 4, linebackers 3, secondary 4). Never judge a room by its " \
    "backups. Starter average is shown to one decimal, so a tie really is a tie.",
    "Open every position with the headline (strongest of ours, weakest of ours, most improved), then pick two " \
    "or three storylines for the room and move on. Do not read the tables, and do not cover every team's " \
    "every bullet.",
    "'Vs. last year' compares a room's starters now to the same program's starters a year ago, and the riser " \
    "and faller are the starters whose rating moved most. If no comparison is listed, don't invent one.",
    "ALWAYS say where a player came from when it's listed: 'transferred from X' and 'true freshman'. Mention " \
    "it every time one of those players is named, since it's part of who they are.",
    "Last Season's Production is only available for our own teams: the room's top returning producer and the " \
    "top producer who left. Use it for what the team gains and loses. Never quote stats for another school, " \
    "and never invent any.",
    "NIL is shown in dollars with its rank in the conference. Worth a line when spending and results line up " \
    "or clash (a big spender with a weak room, a bargain with a strong one); skip it otherwise.",
    "The conference line is one beat of context, not a segment. Ratings are only reliable for colleges with a " \
    "roster on file (listed under Data Coverage). Nobody's hidden potential is known, so never speculate about it."
  ].freeze

  VERDICT_RULES = [
    "Close the whole episode with a real debate: the hosts rank our teams' rosters from worst to best and each " \
    "gives every team a one-line tag picked from: #{VERDICT_TAGS.map { |t| t.split(' — ').first }.join(', ')} " \
    "(strongest). They don't have to agree on the order or a tag — a split verdict is good radio.",
    "The closing section lists the teams' numbers side by side in no particular order. Nobody has handed the " \
    "hosts a ranking; they argue it out from the evidence: overall rating, how many rooms sit in the " \
    "conference's top or bottom three, who improved the most from last year, and who is leaning on transfers " \
    "or true freshmen. Each host should defend a position and concede a point."
  ].freeze

  def initialize(data)
    @data = data
  end

  def to_markdown
    lines = []
    lines.concat(PodcastShow.directive_lines(show_name: show_name))
    lines.concat(rule_lines("## 🏈 ROSTER BREAKDOWN FORMAT (PRODUCER NOTE, DO NOT READ ALOUD)", ROSTER_RULES))
    lines.concat(rule_lines("## 🏠 VERDICT FORMAT (PRODUCER NOTE, DO NOT READ ALOUD)", VERDICT_RULES))
    lines.concat(PodcastShow.opening_script_lines(show_name: show_name, framing_hint: "the #{year} roster, position by position, right after spring practice"))
    lines.concat(PodcastShow.run_of_show_lines(segments))
    lines << "# 🏈 ROSTER BREAKDOWN: #{show_name} — #{year} SEASON"
    lines << ""
    lines << "> #{timing_note}"
    lines << ""
    lines.concat(data_coverage_section)
    lines.concat(standing_section)
    @data[:positions].each { |position| lines.concat(position_section(position)) }
    lines.concat(closing_section)
    lines.join("\n")
  end

  private

  def show_name
    @data[:season][:dynasty]
  end

  def year
    @data[:season][:year]
  end

  # Anchors the hosts in time: a concrete date, the new season's year, and
  # which season "last year" means, so they don't treat the previous
  # season's results as this one's or talk as if games have been played.
  def timing_note
    pretty = Date.parse(@data[:broadcast_date]).strftime("%A, %B %-d, %Y")
    "**Broadcast date:** #{pretty} — the end of April, right after spring practice. This is the #{year} season: " \
      "it hasn't started and no #{year} games have been played. 'Last season' and 'last year' mean #{@data[:last_season_year]}. " \
      "Anchor every 'when' reference (this spring, this summer, this fall, the opener) to this date."
  end

  def rule_lines(title, rules)
    [ title, "", *rules.map { |rule| "- #{rule}" }, "" ]
  end

  def segments
    [ "Where Each Team Stands" ] + @data[:positions].map { |p| p[:position_group] } + [ "Final Verdicts: Ranking Our Rosters" ]
  end

  def data_coverage_section
    coverage = @data[:data_coverage]
    lines = [ "## 📋 DATA COVERAGE (PRODUCER NOTE, DO NOT READ ALOUD)", "" ]
    lines << "> #{coverage[:note]}"
    lines << ">"
    lines << "> **Rosters we have:** #{coverage[:rostered_colleges].join(', ')}"
    lines << "> **Last season on record:** #{coverage[:last_season_available] ? 'yes' : 'no — skip every comparison to last year'}"
    lines << ""
    lines
  end

  # ---- opening: where each team stands -----------------------------------

  def standing_section
    lines = [ "---", "", "## 📍 WHERE EACH TEAM STANDS", "" ]
    @data[:teams].each { |team| lines.concat(standing_lines(team)) }
    lines
  end

  def standing_lines(team)
    ratings = team[:ratings]
    lines = [ "### #{team[:college][:name]} (Coach: #{team[:coach][:name]})" ]
    lines << "- Team ratings: #{ratings[:overall] || '—'} overall (#{ratings[:offense] || '—'} offense, #{ratings[:defense] || '—'} defense)" \
             "#{rank_text(ratings[:conference_rank], ", ", " in the #{team[:college][:conference]}")}#{change_text(ratings[:change_from_last_year], ' from last year')}"
    last = team[:last_season]
    lines << "- Last season: #{record(last[:wins], last[:losses])}#{conference_record(last)}" if last && last[:wins]
    lineup = team[:starting_lineup]
    if lineup[:transfers].positive? || lineup[:true_freshmen].positive? || lineup[:returning].positive?
      lines << "- Starting lineup (#{lineup[:total]} starters across every room): #{lineup[:returning]} returning, " \
               "#{lineup[:transfers]} transfer#{'s' unless lineup[:transfers] == 1}, " \
               "#{lineup[:true_freshmen]} true freshm#{lineup[:true_freshmen] == 1 ? 'an' : 'en'}"
    end
    lines << ""
    lines
  end

  def record(wins, losses)
    "#{wins}-#{losses}"
  end

  def conference_record(last)
    last[:conference_wins] ? " (#{record(last[:conference_wins], last[:conference_losses])} in conference)" : ""
  end

  # ---- positions -------------------------------------------------------------

  def position_section(position)
    lines = [ "---", "", "## 🎯 #{position[:position_group].upcase}", "" ]
    lines.concat(headline_lines(position))
    position[:our_teams].each { |team| lines.concat(team_room_lines(team)) }
    lines.concat(conference_lines(position[:conference]))
    lines
  end

  def headline_lines(position)
    lines = []
    lines << "- 💪 **Strongest of ours:** #{headline_team(position[:strongest_of_ours])}" if position[:strongest_of_ours]
    lines << "- ⚠️ **Weakest of ours:** #{headline_team(position[:weakest_of_ours])}" if position[:weakest_of_ours]
    if position[:most_improved]
      lines << "- 📈 **Most improved:** #{position[:most_improved][:college][:name]} (#{signed(position[:most_improved][:change])} vs. last year's starters)"
    end
    lines << ""
    lines
  end

  def headline_team(entry)
    "#{entry[:college][:name]} (#{entry[:starter_average]} starter average#{rank_text(entry[:conference_rank], ', ')})"
  end

  def team_room_lines(team)
    lines = [ "**#{team[:college][:name]}** (Coach: #{team[:coach][:name]})" ]
    if team[:starters].empty?
      return lines + [ "- No rated starters on file.", "" ]
    end

    lines << "- Starters: #{team[:starters].map { |p| starter_text(p) }.join('; ')}"
    lines << "- Starter average #{team[:starter_average]}#{rank_text(team[:conference_rank], ' — ', ' in the conference')}" \
             "#{last_year_text(team[:last_year])}"
    lines.concat(mover_lines(team[:movers]))
    lines << "- NIL: #{nil_text(team[:nil_spend])}" if team[:nil_spend]
    lines << "- All-Americans: #{team[:all_americans].map { |aa| "#{aa[:name]} (#{honor_label(aa)}#{origin_suffix(aa[:origin])})" }.join(', ')}" if team[:all_americans].any?
    lines.concat(production_lines(team[:last_season_production]))
    lines << ""
    lines
  end

  def starter_text(player)
    "#{player[:name]} (#{player[:overall]} OVR, #{player[:class_year]}#{origin_suffix(player[:origin])})"
  end

  # "transferred from X" / "true freshman" — a returning or unknown origin
  # adds nothing worth saying.
  def origin_suffix(origin)
    return "" unless origin

    case origin[:type]
    when "transfer" then ", transferred from #{origin[:from_college]}"
    when "true_freshman" then ", true freshman"
    else ""
    end
  end

  def last_year_text(last_year)
    return "" unless last_year && last_year[:change]
    return " (unchanged from last year's starters)" if last_year[:change].zero?

    " (#{signed(last_year[:change])} vs. last year's starters, who averaged #{last_year[:starter_average]})"
  end

  FALLER_THRESHOLD = -3

  def mover_lines(movers)
    lines = []
    riser = movers[:riser]
    lines << "- Biggest riser among the starters: #{mover_text(riser)}" if riser
    faller = movers[:faller]
    lines << "- Biggest drop among the starters: #{mover_text(faller)}" if faller && faller[:overall_change] <= FALLER_THRESHOLD
    lines
  end

  def mover_text(player)
    "#{player[:name]} (#{player[:position]}, #{signed(player[:overall_change])} to #{player[:overall]} OVR#{origin_suffix(player[:origin])})"
  end

  def nil_text(nil_spend)
    "#{currency(nil_spend[:dollars])} — #{ordinal(nil_spend[:rank])} of #{nil_spend[:of]} in the conference (conference average #{currency(nil_spend[:conference_average])})"
  end

  def production_lines(production)
    return [] unless production

    lines = []
    returning = production[:returning_leader]
    lines << "- Last season's top returning producer: #{producer_text(returning)}" if returning
    lost = production[:lost_leader]
    lines << "- Last season's top producer who is gone: #{producer_text(lost)}" if lost
    lines
  end

  def producer_text(producer)
    now = producer[:current_overall] ? ", now #{producer[:current_overall]} OVR #{producer[:current_class_year]}" : ""
    "#{producer[:name]} (#{producer[:position]}) — #{producer[:stat_line]}#{now}"
  end

  def conference_lines(conference)
    lines = [ "**Around the conference:**" ]
    if conference[:top_rooms].present?
      lines << "- Best rooms: #{conference[:top_rooms].map { |r| "#{r[:college][:name]} (#{r[:average]})#{r[:coached_by_us] ? ' — ours' : ''}" }.join(', ')}"
    end
    if (best = conference[:best_player])
      lines << "- Best player on file: #{best[:name]}, #{best[:college][:name]} (#{best[:overall]} OVR#{origin_suffix(best[:origin])})#{best[:coached_by_us] ? ' — ours' : ''}"
    end
    if conference[:all_americans].present?
      lines << "- All-Americans: #{conference[:all_americans].map { |aa| "#{aa[:name]} (#{aa[:college][:name]}, #{honor_label(aa)}#{origin_suffix(aa[:origin])})" }.join(', ')}"
    end
    if conference[:nil_leaders].present?
      lines << "- NIL spend leaders: #{conference[:nil_leaders].map { |e| "#{e[:college][:name]} (#{currency(e[:amount])})" }.join(', ')}"
    end
    lines << ""
    lines
  end

  def honor_label(all_american)
    scope = all_american[:national] ? "National" : all_american[:conference]
    tier = all_american[:tier] == 1 ? "1st Team" : "2nd Team"
    preseason = all_american[:preseason] ? "Preseason " : ""
    "#{preseason}#{scope} #{tier}"
  end

  # ---- closing -----------------------------------------------------------------

  def closing_section
    lines = [ "---", "", "## 🏠 FINAL VERDICTS: RANKING OUR ROSTERS", "" ]
    lines << "Our teams side by side, in alphabetical order. This is NOT a ranking — the hosts debate and decide it."
    lines << ""
    @data[:team_comparison].each { |entry| lines.concat(comparison_lines(entry)) }
    lines
  end

  def comparison_lines(entry)
    rank = rank_text(entry[:overall_conference_rank], " (", " in the conference)")
    lines = [ "- **#{entry[:college][:name]}**: #{entry[:overall] || '—'} overall#{rank}; " \
              "#{rooms(entry[:rooms_in_conference_top_3])} in the conference's top three, " \
              "#{entry[:rooms_in_conference_bottom_3]} in its bottom three" ]
    lines[0] += "; starting rooms changed by an average of #{signed(entry[:average_room_change])} from last year" if entry[:average_room_change]
    lines << "  - Best rooms: #{room_ranks(entry[:best_rooms])}"
    lines << "  - Worst rooms: #{room_ranks(entry[:worst_rooms])}"
    lines << ""
    lines
  end

  def rooms(count)
    "#{count} room#{'s' unless count == 1}"
  end

  def room_ranks(rooms)
    rooms.map { |r| "#{r[:position_group]} (#{ordinal(r[:rank])} of #{r[:of]})" }.join(", ")
  end

  # ---- formatting helpers ----------------------------------------------------

  # " — 2nd of 14 in the conference", or "" when there's no rank.
  def rank_text(rank, prefix, suffix = "")
    return "" unless rank

    "#{prefix}#{ordinal(rank[:rank])} of #{rank[:of]}#{suffix}"
  end

  def change_text(change, suffix)
    return "" if change.nil?

    "; #{change.zero? ? 'unchanged' : "#{change.positive? ? 'up' : 'down'} #{change.abs}"}#{suffix}"
  end

  def signed(number)
    number.positive? ? "+#{number}" : number.to_s
  end

  def ordinal(number)
    return "#{number}th" if (11..13).cover?(number % 100)

    "#{number}#{{ 1 => 'st', 2 => 'nd', 3 => 'rd' }.fetch(number % 10, 'th')}"
  end

  def currency(amount)
    return "—" if amount.blank?

    ActiveSupport::NumberHelper.number_to_currency(amount, precision: 0)
  end
end
