# Renders the WinTotalsSerializer payload as Markdown, meant for feeding
# into an LLM-based podcast generator (e.g. NotebookLM) rather than JSON.
# Unlike the other broadcast shows, this one is scripted as a schedule
# read-through — game by game, in order — rather than a big-picture team
# overview. Most games get called outright (LIKELY WIN / LIKELY LOSS); only
# the COIN FLIP games are actual debates. See DEBATE_RULES below.
class WinTotalsMarkdownPresenter
  PROJECTION_LABELS = {
    likely_win: "✅ LIKELY WIN",
    likely_loss: "❌ LIKELY LOSS",
    coin_flip: "🎲 COIN FLIP"
  }.freeze

  DEBATE_RULES = [
    "When you reach a team, read their full schedule aloud in order — every week, every opponent, home or away " \
    "— together with the Vegas win total line. This is a schedule preview, not a big-picture overview: don't " \
    "skip straight to a summary.",
    "Move through the schedule in the order it's listed. Every game already tagged LIKELY WIN or LIKELY LOSS " \
    "below is NOT up for debate — call it out in a sentence or two each (why it's basically locked in) and keep moving.",
    "Every game tagged COIN FLIP is a real debate: stop on it. One host argues it's a win, the other argues " \
    "it's a loss, each citing something concrete — the ratings gap, home/away, a specific player matchup, or a " \
    "past head-to-head result. No vague \"I just have a good feeling.\"",
    "Alternate which host takes which side from coin-flip to coin-flip (and from team to team) so it doesn't " \
    "always break the same way — nobody should be able to predict a host's side before they open their mouth.",
    "Once the full schedule is read, both hosts state whether they land over or under the Vegas line based on " \
    "how they see that team's coin-flip games breaking — that's the only resolution for the schedule portion. " \
    "Then close the team's segment with the Hot Seat Check on its head coach (see the hot seat rules below)."
  ].freeze

  HOT_SEAT_RULES = [
    "Every team's segment ends with a Hot Seat Check on its head coach: how safe his job is if the team hits " \
    "the number, and what happens if it doesn't. Do it AFTER the over/under call, using the Hot Seat " \
    "Thermometer block under each team.",
    "Say the thermometer reading out loud — ICE COLD, COOL, WARM, HOT, or ON FIRE. Never say the job-security " \
    "percentage; it's backstage. Talk like a sportsbook that also tracks coaching changes: 'if he goes under, " \
    "he's most likely out of a job at the end of the year.'",
    "Be definitive where the block is. If it says finishing under the number puts him OUT, say he's most " \
    "likely out. If it says hitting the number leaves him HOT, say a .500-type year doesn't save him. Use the " \
    "'wins needed to keep his job' number as the headline.",
    "The buyout is the cost of firing him. Give it in dollars and compare it to the other coaches' buyouts: a " \
    "big number can buy a struggling coach another year, a small one makes the move easy.",
    "The Early Test only appears when the coach could be shown the door early. Name the opening games and the " \
    "bye week, and say what a loss means: 'drop either one and he could be out by the Week 3 bye.' When the " \
    "block says EASY START, make a point that a loss in those games would be damning.",
    "A coach reading ICE COLD or COOL gets one quick line and the buyout, nothing more. Don't invent drama " \
    "that isn't in the block, and don't speculate about boosters, contracts or anything not listed here."
  ].freeze

  # This show kept coming out sounding like a data-science readout instead
  # of a betting show — hosts would literally say "the model" and "the
  # algorithm." These rules exist specifically to kill that.
  VEGAS_TONE_RULES = [
    "This is a Vegas sportsbook debate show, not a stats presentation. The words \"model,\" \"algorithm,\" " \
    "\"data,\" \"formula,\" \"probability,\" and \"rating system\" DO NOT EXIST in this universe and must never " \
    "be said out loud. Everything in this document is backstage prep for the hosts, not a script to read from.",
    "Never say a percentage or a rating number out loud. Translate it into how oddsmakers and bettors actually " \
    "talk: a lopsided game is a \"lock\" or a \"lay-it-down favorite,\" a sneaky-tough one is a \"trap game\" or " \
    "a \"letdown spot,\" a close one is a \"pick 'em.\"",
    "Build arguments out of scouting and betting language, not stats-speak: schedule spots, revenge games, " \
    "get-right games, home cooking, a defense that travels well, a shaky line on the road, a team that's live " \
    "underdog value. If a host would sound like a broadcast from a research lab, rewrite the line."
  ].freeze

  def initialize(data)
    @data = data
  end

  def to_markdown
    lines = []
    lines.concat(PodcastShow.directive_lines(show_name: show_name))
    lines.concat(debate_format_lines)
    lines.concat(hot_seat_format_lines)
    lines.concat(vegas_tone_lines)
    lines.concat(PodcastShow.opening_script_lines(show_name: show_name, framing_hint: "how many games each of our teams will actually win"))
    lines.concat(PodcastShow.run_of_show_lines(segments))
    lines << "# 🥊 WIN TOTALS: OVER/UNDER — #{show_name} — #{@data[:season][:year]}"
    lines << ""
    lines << "> #{producer_note}"
    lines << ""

    @data[:teams].each { |team| lines.concat(team_section(team)) }

    lines.concat(conference_landscape_section)
    lines.concat(champion_predictions_section)

    lines.join("\n")
  end

  private

  def show_name
    @data[:season][:dynasty]
  end

  def producer_note
    "PRODUCER NOTE: This is a schedule preview, not a big-picture team overview — for each team, read the full " \
      "schedule game by game. Every game is pre-tagged LIKELY WIN, LIKELY LOSS, or COIN FLIP by the house. Called " \
      "games get a quick line, coin flips get a real debate — see the tone notes above before you write a word " \
      "of script. The Vegas win total itself is shaded to a half-point so there's always a clean over/under, and " \
      "each team closes with a Hot Seat Check on its head coach. No " \
      "games have been played yet — this is pure preseason projection. Last season's record is included " \
      "wherever we have one (won't show up for a program's first season on the show, but will from year two onward)."
  end

  def debate_format_lines
    lines = [ "## 🥊 DEBATE FORMAT (PRODUCER NOTE, DO NOT READ ALOUD)", "" ]
    DEBATE_RULES.each { |rule| lines << "- #{rule}" }
    lines << ""
    lines
  end

  def hot_seat_format_lines
    lines = [ "## 🌡️ HOT SEAT FORMAT (PRODUCER NOTE, DO NOT READ ALOUD)", "" ]
    HOT_SEAT_RULES.each { |rule| lines << "- #{rule}" }
    lines << ""
    lines
  end

  def vegas_tone_lines
    lines = [ "## 🎰 TONE — THIS IS A SPORTSBOOK, NOT A LAB (PRODUCER NOTE, DO NOT READ ALOUD)", "" ]
    VEGAS_TONE_RULES.each { |rule| lines << "- #{rule}" }
    lines << ""
    lines
  end

  def segments
    team_segments = @data[:teams].map do |t|
      coin_flips = t[:schedule_summary][:coin_flips]
      "#{t[:college][:name]} — Schedule Read + #{pluralize(coin_flips, 'Coin-Flip Debate')} + Hot Seat Check (Line: #{format_line(t[:vegas_win_total])})"
    end
    team_segments + [ "Around the Conference: Other Win Totals", "Conference Champion Predictions" ]
  end

  def team_section(team)
    lines = []
    lines << "---"
    lines << ""
    lines << "## 🎯 #{team[:college][:name]} (Coach: #{team[:coach][:name]}) — VEGAS LINE: #{format_line(team[:vegas_win_total])}"
    lines << "**Conference:** #{team[:college][:conference]}" if team[:college][:conference]
    lines << "**Ratings:** #{ratings_line(team[:ratings])}"
    last_season = record_line(team[:previous_season_record])
    lines << "**Last Season:** #{last_season}" if last_season
    lines << "**Schedule Snapshot:** #{schedule_summary_line(team[:schedule_summary])}"
    outlook = outlook_line(team[:outlook])
    lines << "**Outlook:** #{outlook}" if outlook
    lines << ""

    lines.concat(schedule_section(team[:schedule]))
    lines.concat(key_players_section(team[:key_players]))
    lines.concat(position_group_section(team[:position_group_averages]))
    lines.concat(hot_seat_section(team[:hot_seat]))

    lines
  end

  def outlook_line(outlook)
    return nil unless outlook

    "#{likelihood(outlook[:chance_over])} to go over the line, #{likelihood(outlook[:chance_bowl_eligible])} to reach " \
      "bowl eligibility (6 wins), #{likelihood(outlook[:chance_losing_season])} to finish with a losing record " \
      "(backstage: about #{outlook[:expected_wins]} expected wins)"
  end

  # Plain-English odds for the hosts; the exact percentage stays backstage.
  def likelihood(chance)
    case chance
    when 0.85.. then "a near-lock"
    when 0.65...0.85 then "likely"
    when 0.35...0.65 then "a toss-up"
    when 0.15...0.35 then "unlikely"
    else "a long shot"
    end
  end

  def hot_seat_section(hot_seat)
    return [] unless hot_seat

    coach = hot_seat[:coach]
    lines = [ "### 🌡️ Hot Seat Thermometer — #{coach[:name]}", "" ]
    lines << "- **Reading right now: #{coach[:reading]}** (the game lists his job security as #{coach[:label]}; " \
             "backstage: #{coach[:job_security]}%)"
    lines << buyout_line(coach)
    number = hot_seat[:number]
    lines << "- The number: #{format_line(number[:line])} — he has to win #{number[:wins_to_hit]} to hit it"
    lines << "- **Wins needed to keep his job: #{hot_seat[:wins_needed_to_keep_job]}**"
    lines << "- If he hits the number (#{record(hot_seat[:at_the_number])}): #{seat_result(hot_seat[:at_the_number])}"
    if hot_seat[:one_win_under]
      lines << "- If he finishes one win under (#{record(hot_seat[:one_win_under])}): #{seat_result(hot_seat[:one_win_under])}"
    end
    lines << "- Chance he finishes under the number: #{likelihood(hot_seat[:chance_of_finishing_under])}"
    lines << "- Where each finish leaves him:"
    likeliest = hot_seat[:ladder].max_by { |o| o[:probability] }
    hot_seat[:ladder].each do |o|
      note = o.equal?(likeliest) ? " — the single most likely finish" : ""
      lines << "  - #{record(o)}: #{o[:reading]} (#{o[:label]})#{note}"
    end
    lines.concat(early_test_lines(hot_seat[:early_test], coach))
    lines << ""
    lines
  end

  def record(outcome)
    "#{outcome[:wins]}-#{outcome[:losses]}"
  end

  def seat_result(outcome)
    return "#{outcome[:reading]} — most likely out of a job at the end of the season" if outcome[:out]

    survives = case outcome[:label]
    when "Hot Seat" then "survives, but the seat is still hot"
    when "Low" then "survives, but the seat is still warm"
    else "keeps his job comfortably"
    end
    "#{outcome[:reading]} (#{outcome[:label]}) — #{survives}"
  end

  # The buyout is what it would cost to move on from him, ranked against our
  # other coaches so the hosts can compare.
  def buyout_line(coach)
    return "- Buyout: not available" unless coach[:buyout_dollars]

    buyouts = @data[:teams].filter_map { |t| t.dig(:hot_seat, :coach, :buyout_dollars) }.sort
    rank = buyouts.index(coach[:buyout_dollars]) + 1
    placement = buyouts.size > 1 ? (rank == 1 ? " — the cheapest of our coaches" : (rank == buyouts.size ? " — the most expensive of our coaches" : "")) : ""
    "- Buyout: #{currency(coach[:buyout_dollars])}#{placement}"
  end

  def early_test_lines(early, coach)
    return [] unless early

    games = early[:games].map { |g| "Week #{g[:week_number]} #{g[:home] ? 'vs' : '@'} #{g[:opponent]} (#{PROJECTION_LABELS.fetch(g[:projection], '')})" }
    point = early[:decision_point]
    deadline = point[:kind] == "bye" ? "the Week #{point[:week]} bye" : "after Week #{point[:week]}"
    stakes =
      if early[:allowed_losses].zero?
        "he can't afford to lose any of them"
      else
        "he can lose at most #{early[:allowed_losses]} of them"
      end
    lines = [ "- **Early test (before #{deadline}):** #{games.join('; ')}" ]
    lines << "  - #{stakes} — he needs #{early[:wins_needed]} of #{early[:games].size}; drop more and he could be out of a job by #{deadline}"
    lines << "  - EASY START: every game in this stretch is a likely win, so a loss here would be damning" if early[:easy_start]
    lines << "  - Chance he's gone by then: #{likelihood(early[:chance_of_exit])}"
    lines
  end

  def currency(amount)
    ActiveSupport::NumberHelper.number_to_currency(amount, precision: 0)
  end

  def schedule_summary_line(summary)
    return "—" unless summary

    "#{pluralize(summary[:likely_wins], 'likely win')}, #{pluralize(summary[:likely_losses], 'likely loss', 'likely losses')}, " \
      "#{pluralize(summary[:coin_flips], 'coin-flip game')}"
  end

  def pluralize(count, singular, plural = nil)
    word = count == 1 ? singular : (plural || "#{singular}s")
    "#{count} #{word}"
  end

  def ratings_line(ratings)
    return "—" unless ratings

    "Overall #{ratings[:overall]}, Offense #{ratings[:offense]}, Defense #{ratings[:defense]}"
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

    players.map { |p| "- #{p[:name]} (#{p[:position]}, #{p[:overall]} OVR, #{p[:class_year]})" }
  end

  def position_group_section(averages)
    return [] if averages.blank?

    lines = [ "### 📊 Position Group Averages", "" ]
    averages.each { |group, average| lines << "- #{group}: #{average} avg" }
    lines << ""
    lines
  end

  def schedule_section(schedule)
    lines = [ "### 🗓️ Full Schedule", "" ]
    return lines + [ "- Schedule not yet set.", "" ] if schedule.blank?

    schedule.each { |game| lines.concat(game_bullets(game)) }
    lines << ""
    lines
  end

  def game_bullets(game)
    where = game[:home] ? "vs" : "@"
    opp_ratings = game[:opponent_ratings]
    opp_summary = opp_ratings ? "#{opp_ratings[:overall]} OVR (#{opp_ratings[:offense]} OFF / #{opp_ratings[:defense]} DEF)" : "no rating data"
    last_season = record_line(game[:opponent_previous_season_record])
    last_season_note = last_season ? ", last season #{last_season}" : ""
    lean = game[:win_probability] ? "house lean: #{(game[:win_probability] * 100).round}%" : "house lean unknown"
    label = PROJECTION_LABELS.fetch(game[:projection], "")

    lines = []
    lines << "- #{label} — **Week #{game[:week_number]} #{where} #{game[:opponent][:name]}** " \
             "— #{opp_summary}#{last_season_note} — #{lean}"
    lines.concat(opponent_key_players_bullets(game[:opponent_key_players]))
    lines.concat(previous_meetings_bullets(game[:previous_meetings]))
    lines
  end

  def opponent_key_players_bullets(key_players)
    return [] if key_players.blank?

    offense = key_players[:offense].first(2).map { |p| "#{p[:name]} (#{p[:position]}, #{p[:overall]})" }.join(", ")
    defense = key_players[:defense].first(2).map { |p| "#{p[:name]} (#{p[:position]}, #{p[:overall]})" }.join(", ")
    lines = []
    lines << "  - Their offense: #{offense}" if offense.present?
    lines << "  - Their defense: #{defense}" if defense.present?
    lines
  end

  def previous_meetings_bullets(meetings)
    return [] if meetings.blank?

    lines = [ "  - Previous meetings:" ]
    meetings.each do |m|
      lines << "    - #{m[:year]}: #{m[:home][:name]} #{m[:home][:score]} — #{m[:away][:name]} #{m[:away][:score]}"
    end
    lines
  end

  def conference_landscape_section
    return [] if @data[:conference_landscape].blank?

    lines = []
    @data[:conference_landscape].each do |group|
      next if group[:teams].blank?

      lines << "---"
      lines << ""
      lines << "## 🏟️ AROUND THE #{group[:conference].upcase}"
      lines << ""
      lines << "Brief mention only — projected win totals for the rest of the #{group[:conference]}, for context. " \
               "A team marked NO LINE YET doesn't have its full schedule on file, so don't invent a win total for it; " \
               "place it by its power rating and last season instead:"
      lines << ""
      group[:teams].each do |team|
        last_season = record_line(team[:previous_season_record])
        last_season_note = last_season ? ", last season #{last_season}" : ""
        detail = "#{team[:overall]} OVR, #{team[:power_rating]} power rating#{last_season_note}"
        line = team[:vegas_win_total] ? format_line(team[:vegas_win_total]) : "NO LINE YET"
        lines << "- #{team[:college][:name]}: #{line} (#{detail})"
      end
      lines << ""
    end
    lines
  end

  def champion_predictions_section
    return [] if @data[:champion_predictions].blank?

    lines = [ "---", "", "## 🏆 CONFERENCE CHAMPION PREDICTIONS", "" ]
    lines << "For each conference, name the two teams that meet in the championship game, then say who the " \
             "favorite is and how big a favorite (see below). The title-game teams are the two strongest in the conference."
    lines << ""
    @data[:champion_predictions].each { |prediction| lines.concat(champion_prediction_bullets(prediction)) }
    lines
  end

  EDGE_WORDS = {
    "clear" => "a clear favorite",
    "slight" => "a slight favorite",
    "pick_em" => "barely a favorite — this one is a pick 'em"
  }.freeze

  # Each conference gets a championship game: the two strongest teams, then
  # who the hosts should call the favorite.
  def champion_prediction_bullets(prediction)
    lines = [ "**#{prediction[:conference]} Championship Game:**" ]
    game = prediction[:championship_game]

    if game
      first, second = game[:teams]
      lines << "- The matchup: #{first[:college][:name]} vs. #{second[:college][:name]}"
      game[:teams].each { |team| lines << "  - #{finalist_line(team)}" }
      favorite = game[:favorite][:college][:name]
      lines << "- **Favorite: #{favorite}** — #{EDGE_WORDS.fetch(game[:edge])} over #{game[:underdog][:college][:name]} " \
               "(backstage: about #{(game[:favorite_chance] * 100).round}%)"
    end

    shot = prediction[:our_best_shot]
    if shot
      last_season = record_line(shot[:previous_season_record])
      last_season_note = last_season ? ", last season #{last_season}" : ""
      lines << "- Best of ours, but not in the title game: #{shot[:college][:name]} " \
               "(#{ordinal(shot[:rank])}-strongest in the conference, #{shot[:team_strength]} power rating#{last_season_note})"
    end

    lines << ""
    lines
  end

  def finalist_line(team)
    last_season = record_line(team[:previous_season_record])
    last_season_note = last_season ? ", last season #{last_season}" : ""
    coach = team[:coach] ? ", Coach #{team[:coach][:name]}" : ""
    note = team[:coached_by_us] ? " — one of ours!" : ""
    "#{team[:college][:name]} (#{team[:team_strength]} power rating#{last_season_note}#{coach})#{note}"
  end

  def ordinal(number)
    return "#{number}th" if (11..13).cover?(number % 100)

    "#{number}#{{ 1 => 'st', 2 => 'nd', 3 => 'rd' }.fetch(number % 10, 'th')}"
  end

  def record_line(record)
    return nil unless record

    conf = record[:conference_wins].present? && record[:conference_losses].present? ? " (#{record[:conference_wins]}-#{record[:conference_losses]} conf)" : ""
    "#{record[:wins]}-#{record[:losses]}#{conf}"
  end

  def format_line(number)
    return "—" unless number

    number % 1 == 0 ? "#{number.to_i}.0" : number.to_s
  end
end
