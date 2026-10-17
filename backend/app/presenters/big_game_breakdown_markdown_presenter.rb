# Renders the BigGameBreakdownSerializer payload as Markdown, meant for
# feeding into an LLM-based podcast generator (e.g. NotebookLM). The show is
# the midweek preview: each of our games gets the stakes, a film room, a
# quarterback duel and each host's single bet, ordered so the closest game
# comes last. The bets themselves are assigned by the server (see
# BigGameBreakdown::PickLocker) so they can be scored later; the hosts argue
# them rather than choose them.
class BigGameBreakdownMarkdownPresenter
  SHOW_NAME = BigGameBreakdown::SHOW_NAME

  FORMAT_RULES = [
    "Every game follows the same four beats, in this order: THE STAKES (what's riding on it, how each team got " \
    "here, the history), THE FILM ROOM (the position matchups that decide it, the key players, and any injuries), " \
    "THE QUARTERBACK DUEL, and THE PICK. The pick is the last thing said about each game.",
    "Games are listed least interesting first and closest last. Move through them in the order given and let the " \
    "energy build: lopsided games get a tighter segment, and the final game, the closest line on the board, gets " \
    "the longest runtime and the biggest finish.",
    "Never say anything twice. A point made in the stakes is not repeated in the film room, and the pick is NOT a " \
    "recap: it's the line, each host's side, and at most one fresh reason each. If the reason was already said " \
    "earlier in the segment, find a new one or just say the bet.",
    "Each host has exactly one bet per game, already decided and written out under THE PICK as a mandatory " \
    "dialogue beat. BOTH hosts must say their call out loud, in their own voice but with the exact team, side and " \
    "number written there (\"Marshall minus seventeen and a half,\" \"the Over at fifty-five and a half\"), and " \
    "they must do it before moving on to the next game. Never skip it, never switch a side or hedge. When both " \
    "hosts have the same side, it's a love-fest; when they split, it's a fight. Never reveal that the bets were " \
    "handed out.",
    "After the last game's pick, go straight to the NEXT EPISODE tease. Do NOT recap the bets: they were all just " \
    "said out loud, game by game. Tease the reactions episode on the date shown, where we react to how these " \
    "games played out.",
    "Mention games elsewhere only when they're listed under \"Elsewhere\" for a game, and only as a quick note on " \
    "how they bear on this one. Don't preview other games during the main segments. The only time other games get " \
    "airtime is the ALSO ON THE BOARD heads-up at the end of the show, and it is strictly a heads-up.",
    "Only talk about conference standings and the poll when a game's data includes them. Never invent a ranking, a " \
    "streak or a head-to-head result that isn't written below. If a game has no previous meetings, say nothing " \
    "about history.",
    "Injuries are part of the film room, not a segment of their own. An injury marked OUT matters; one marked " \
    "RETURNING is good news worth a line; skip the section entirely when there are none.",
    "When a Heisman candidate is on the field (the Heisman watch line in a game's stakes), make it a storyline: " \
    "what it means for the opposing defense to face him, or for our team if he's ours, and how his production " \
    "backs it up. Only name players listed there; never invent a candidate.",
    "Any thoughts on a team's recent performance belong where they fit (the stakes, the film room, the " \
    "quarterback duel) rather than in a separate section, and there are no separate \"upset alert\" or \"trap " \
    "game\" segments. If a host feels one, a single sentence in the stakes is enough."
  ].freeze

  def initialize(data)
    @data = data
  end

  def to_markdown
    lines = []
    lines.concat(PodcastShow.directive_lines(show_name: SHOW_NAME))
    lines.concat(show_brief_lines)
    lines.concat(format_lines)
    lines.concat(tone_lines)
    lines.concat(PodcastShow.opening_script_lines(show_name: SHOW_NAME, framing_hint: "the games on the board this week"))
    lines.concat(PodcastShow.run_of_show_lines(segments))
    lines << "# 🏈 BIG GAME BREAKDOWN — Week #{@data.dig(:week, :number)} — #{@data.dig(:season, :year)}"
    lines << ""
    lines.concat(date_lines)
    lines << "> #{@data.dig(:focus, :instructions)}"
    lines << ""
    lines.concat(poll_note_lines)
    lines.concat(scoreboard_lines)

    games.each_with_index { |game, index| lines.concat(game_section(game, index)) }
    lines.concat(also_on_lines) if games.any?
    lines.concat(next_episode_lines) if games.any?

    lines.join("\n")
  end

  private

  def games
    @data[:games]
  end

  # What the episode is and how the time is spent, up front, so the hosts
  # stay on the games instead of drifting into big-picture talk and rushing
  # the picks. Written to hold up even when the producer's own request is
  # short or says something different.
  def show_brief_lines
    return [] if games.empty?

    lines = [ "## 🎯 SHOW BRIEF (READ FIRST, DO NOT READ ALOUD)", "",
              "This episode is the #{games.size} game#{'s' if games.size != 1} below, in this exact order#{', plus a short heads-up on other games at the very end' if also_on.any?}. There is no " \
              "big-picture season talk, no general college football discussion and no state-of-the-sport opening: the " \
              "opening line sets the scene, and everything after it is about these games.", "" ]
    step = 0
    lines << "#{step += 1}. The mandatory opening, word for word."
    lines << "#{step += 1}. The Card: ONE sentence naming the games on the board, in order. No analysis."
    lines << "#{step += 1}. The Scoreboard: #{recap_label} bets, game by game, about fifteen seconds a game, then each host's season record." if last_week_results.any?
    games.each_with_index do |game, index|
      finale = index == games.size - 1 ? " (THE FINALE)" : ""
      lines << "#{step += 1}. Game #{index + 1}: #{matchup_title(game)}#{finale}. In order: Stakes, Film Room, Quarterback Duel, The Pick."
    end
    lines << "#{step += 1}. Also on the Board: a quick heads-up on the other games listed at the very end. No picks, no predictions." if also_on.any?
    lines << "#{step + 1}. The Next Episode tease. Do not recap the bets."
    lines << ""
    early = last_week_results.any? ? "The opening, the card and the scoreboard together are" : "The opening and the card together are"
    lines << "**PACING.** #{early} roughly the first tenth of the show: get to " \
             "Game 1 quickly. The games share the rest about evenly, with the finale getting roughly double a regular " \
             "game's time. THE PICK is a real beat, not a throwaway: at the end of EACH game, both hosts say their exact " \
             "bet out loud, give one fresh reason, and react to the other host's call (about thirty to forty-five " \
             "seconds), then move on. Never save the picks for the end of the show and never bunch them together."
    lines << ""
    lines << "If any outside request conflicts with this brief on structure or order, follow this brief."
    lines << ""
    lines
  end

  def format_lines
    lines = [ "## 🎙️ SHOW FORMAT (PRODUCER NOTE, DO NOT READ ALOUD)", "" ]
    FORMAT_RULES.each { |rule| lines << "- #{rule}" }
    lines << ""
    lines
  end

  # The same sportsbook-not-a-lab rules the Win Totals show uses, plus a
  # carve-out: scores, records and player production can be said out loud;
  # ratings and probabilities stay backstage.
  def tone_lines
    lines = [ "## 🎰 TONE (PRODUCER NOTE, DO NOT READ ALOUD)", "" ]
    WinTotalsMarkdownPresenter::VEGAS_TONE_RULES.each { |rule| lines << "- #{rule}" }
    lines << "- The point spread, the total, records, scores, streaks and a player's actual production (yards, " \
             "touchdowns, tackles, sacks) are all fair game out loud. Overall ratings, position-group ratings and " \
             "win probabilities are backstage: turn them into a plain-English read."
    lines << ""
    lines
  end

  def segments
    list = [ "The Card — one sentence naming the games on the board, in order. No analysis, no big-picture talk" ]
    list << scoreboard_segment if season_record.present?
    games.each_with_index do |game, index|
      list << "Game #{index + 1}: #{matchup_title(game)} — Stakes, Film Room, Quarterback Duel, The Pick"
    end
    list << also_on_segment if also_on.any?
    list << next_episode_segment if games.any?
    list
  end

  # "No. 13 Arizona State @ Marshall": a ranked team carries its poll number.
  def matchup_title(game)
    "#{ranked_name(game[:away])} @ #{ranked_name(game[:home])}"
  end

  def ranked_name(team)
    name = team[:college][:name]
    team[:ranking] ? "No. #{team[:ranking]} #{name}" : name
  end

  def date_lines
    info = @data[:podcast_date]
    return [] if info.blank?

    pretty = Date.parse(info[:date]).strftime("%A, %B %-d, %Y")
    lines = [ "**Broadcast date:** #{pretty}, ahead of Week #{info[:week_number]}'s games. Anchor every \"when\" " \
              "reference (\"tomorrow night\", \"this Saturday\") to this date." ]
    if info[:review_date]
      review = Date.parse(info[:review_date]).strftime("%A, %B %-d")
      lines << "**Next show:** the Week #{info[:week_number]} reactions episode airs #{review}."
    end
    lines << ""
    lines
  end

  # Rankings come from the latest poll on file; say so when that isn't this
  # week's own (e.g. the preseason poll heading into Week 1).
  def poll_note_lines
    poll_week = @data[:poll_week_number]
    return [] if poll_week.nil? || poll_week == @data.dig(:week, :number)

    [ "> Rankings below are from the latest poll on file (entering Week #{poll_week}), not a fresh one for this week.", "" ]
  end

  # ---- scoreboard --------------------------------------------------------------

  def season_record
    @data.dig(:pick_ledger, :season_record)
  end

  def scoreboard_segment
    if last_week_results.any?
      "The Scoreboard — a quick game-by-game review of #{recap_label} bets (final score, each host's bet, hit or miss, " \
        "one short reaction each), then each host's season record"
    else
      "The Scoreboard — each host's season record on their bets so far"
    end
  end

  # "last week's" normally; "Week 2's" when the most recent bets are older
  # than last week (a week our teams had no games, so no show for it).
  def recap_label
    recap_week = @data.dig(:pick_ledger, :last_week_number)
    current = @data.dig(:week, :number)
    recap_week.nil? || recap_week == current - 1 ? "last week's" : "Week #{recap_week}'s"
  end

  def last_week_results
    @last_week_results ||= Array(@data.dig(:pick_ledger, :last_week)).select { |game| game[:picks].any? { |pick| pick[:result] } }
  end

  # A mandatory, fast recap: hosts reliably give the record and skip the
  # bets themselves unless told to walk through them.
  def scoreboard_lines
    return [] if season_record.blank?

    lines = [ "## 📊 THE SCOREBOARD (MANDATORY DIALOGUE BEAT)", "" ]
    if last_week_results.any?
      lines << "Right after the opening, before the first game, give #{recap_label} bets a quick game-by-game review. " \
               "For EACH game below, in this order: name the game and its final score, say each host's bet and " \
               "whether it hit or missed, and give ONE short reaction each (a jab, a victory lap, a groan, or a " \
               "one-line reason it hit or missed). No re-analysis; about fifteen seconds a game. Then give each " \
               "host's season record. Do NOT skip straight to the records."
      lines << ""
      last_week_results.each { |game| lines << recap_line(game) }
      lines << ""
    end
    lines << "**Season record on bets:**"
    season_record.each { |host, record| lines << "- **#{host}:** #{record_text(record)}" }
    lines << ""
    lines
  end

  def recap_line(game)
    final = game[:home_score] ? " — Final: #{game[:away]} #{game[:away_score]}, #{game[:home]} #{game[:home_score]}" : ""
    bets = game[:picks].map { |pick| "#{pick[:host]}: #{pick[:bet]} — #{pick_result_word(pick[:result])}" }.join(" · ")
    "- #{game[:away]} @ #{game[:home]}#{final}. #{bets}"
  end

  def pick_result_word(result)
    { win: "HIT", loss: "MISSED", push: "PUSH" }.fetch(result, "not graded")
  end

  def record_text(record)
    base = "#{record[:wins]}-#{record[:losses]}"
    record[:pushes].to_i.positive? ? "#{base}-#{record[:pushes]}" : base
  end

  # ---- a game ------------------------------------------------------------------

  def game_section(game, index)
    lines = [ "---", "" ]
    lines << "## 🏈 GAME #{index + 1} OF #{games.size}: #{matchup_title(game)}#{' — THE FINALE' if index == games.size - 1}"
    lines << "**Kickoff:** #{kickoff_text(game[:time])} · #{game[:broadcast]}" if game[:time]
    lines << "**Broadcast:** #{game[:broadcast]}" unless game[:time]
    lines << "**Matchup type:** #{matchup_type(game)}"
    lines.concat(line_lines(game))
    lines.concat(stakes_lines(game))
    lines.concat(film_room_lines(game))
    lines.concat(quarterback_lines(game))
    lines.concat(pick_lines(game))
    lines
  end

  def kickoff_text(time)
    Time.iso8601(time).in_time_zone(PodcastShow::TIME_ZONE).strftime("%a %b %-d, %-I:%M %p ET")
  end

  def matchup_type(game)
    stakes = game[:stakes]
    if game[:both_user_coached] then "Head-to-head between two of our coaches"
    elsif stakes[:conference_game] then "#{stakes[:conference]} conference game"
    else "Non-conference game"
    end
  end

  def line_lines(game)
    line = game[:line]
    where = line[:favorite_is_home] ? "at home" : "on the road"
    [
      "",
      "**THE LINE:** #{line[:favorite]} -#{line[:spread]} (favorite, #{where}) · Total: #{line[:total]}",
      "**How the house sees it:** #{line[:favorite]} is #{confidence_text(line)}",
      *form_lines(line[:form]),
      ""
    ]
  end

  # Results vs. what the roster says, only when it's far enough off to matter.
  # The line already reflects it; this is the story behind the number.
  FORM_NOTABLE_POINTS = 4.0
  FORM_MIN_GAMES = 3

  def form_lines(form)
    notes = [ form[:away], form[:home] ].compact.filter_map do |team|
      next if team[:games] < FORM_MIN_GAMES || team[:points_vs_roster].abs < FORM_NOTABLE_POINTS

      verdict = team[:points_vs_roster].positive? ? "playing better than its roster suggests" : "playing worse than its roster suggests"
      "#{team[:team]} has been #{verdict} over #{team[:games]} game#{'s' unless team[:games] == 1} " \
        "(backstage: #{team[:points_vs_roster].positive? ? '+' : ''}#{team[:points_vs_roster]} points a game vs. expectation)"
    end
    return [] if notes.empty?

    [ "**Form (already priced into the line):**", *notes.map { |note| "- #{note}" } ]
  end

  def confidence_text(line)
    home = line[:home_win_probability]
    favorite = line[:favorite_is_home] ? home : 1 - home
    case favorite
    when 0.85.. then "a lay-it-down favorite"
    when 0.65...0.85 then "a clear favorite"
    when 0.55...0.65 then "a slight lean"
    else "basically a pick 'em"
    end
  end

  # ---- stakes ------------------------------------------------------------------

  def stakes_lines(game)
    lines = [ "### 🔥 THE STAKES", "" ]
    [ game[:away], game[:home] ].each { |team| lines.concat(team_status_lines(team)) }
    lines.concat(heisman_lines(game))
    lines.concat(history_lines(game))
    lines.concat(conference_race_lines(game[:stakes][:conference_race]))
    lines.concat(elsewhere_lines(game[:stakes][:elsewhere]))
    lines << ""
    lines
  end

  def team_status_lines(team)
    name = team[:college][:name]
    coach = team[:coach] ? " (Coach #{team[:coach][:name]}, one of our coaches)" : ""
    rank = team[:ranking] ? "ranked No. #{team[:ranking]}" : "unranked"
    lines = [ "- **#{name}**#{coach}: #{rank}" ]
    lines << "  - **#{@data.dig(:season, :year)} record: #{record_phrase(team[:record])}**"
    lines.concat(conference_record_lines(team[:conference_record]))
    lines << "  - Current streak: #{streak_text(team[:streak])}" if streak_text(team[:streak])
    lines.concat(previous_season_lines(team[:previous_season]))
    lines << "  - Last #{team[:recent_results].size}: #{team[:recent_results].map { |r| result_text(r) }.join(' · ')}" if team[:recent_results].present?
    lines << "  - Scoring: #{team[:scoring][:points_per_game]} points a game, allowing #{team[:scoring][:points_allowed_per_game]}" if team[:scoring]
    lines
  end

  def previous_season_lines(previous)
    return [] unless previous

    conference = previous[:conference_wins] && previous[:conference_losses] ? " (#{previous[:conference_wins]}-#{previous[:conference_losses]} in conference)" : ""
    scoring = previous[:points_per_game] && previous[:points_allowed_per_game] ? ", scoring #{previous[:points_per_game]} and allowing #{previous[:points_allowed_per_game]} a game" : ""
    [ "  - Last season (#{previous[:year]}): #{previous[:wins]}-#{previous[:losses]}#{conference}#{scoring}" ]
  end

  # "1-1 (1 win, 1 loss)": spelled out so the record can't be misread, and
  # "0-0 (no games played yet)" before a team has played.
  def record_phrase(record)
    wins = record[:wins]
    losses = record[:losses]
    return "0-0 (no games played yet)" if wins.zero? && losses.zero?

    "#{wins}-#{losses} (#{wins} #{wins == 1 ? 'win' : 'wins'}, #{losses} #{losses == 1 ? 'loss' : 'losses'})"
  end

  def conference_record_lines(record)
    return [] if record[:wins].zero? && record[:losses].zero?

    [ "  - Conference record: #{record_phrase(record)}" ]
  end

  # "3 wins in a row" / "2 losses in a row"; nil for a streak of one game
  # (the last result is already listed).
  def streak_text(streak)
    return nil unless streak && streak[:length] >= 2

    "#{streak[:length]} #{streak[:kind] == 'W' ? 'wins' : 'losses'} in a row"
  end

  def result_text(result)
    where = result[:home] ? "vs" : "@"
    "#{result[:won] ? 'W' : 'L'} #{result[:team_score]}-#{result[:opponent_score]} #{where} #{result[:opponent]} (Wk #{result[:week_number]})"
  end

  # Heisman candidates on either side. One facing our team (or ours facing a
  # strong defense) is a storyline for the stakes; stay silent when there are
  # none.
  def heisman_lines(game)
    entries = [ game[:away], game[:home] ].flat_map do |team|
      team[:heisman_candidates].map { |player| [ team, player ] }
    end
    return [] if entries.empty?

    lines = [ "- **Heisman watch:**" ]
    entries.each do |team, player|
      owner = team[:user_coached] ? "#{team[:college][:name]} [our coach]" : team[:college][:name]
      lines << "  - #{player_text(player)} — #{owner}"
    end
    lines
  end

  def history_lines(game)
    meetings = game[:stakes][:previous_meetings]
    return [] if meetings.blank?

    series = game[:stakes][:series].map { |name, wins| "#{name} #{wins}" }.join(", ")
    lines = [ "- **History** (series record: #{series}):" ]
    meetings.each do |meeting|
      lines << "  - #{meeting[:year]} Wk #{meeting[:week_number]}: #{meeting[:away][:name]} #{meeting[:away][:score]}, " \
               "#{meeting[:home][:name]} #{meeting[:home][:score]}"
    end
    lines
  end

  def conference_race_lines(race)
    return [] unless race

    lines = [ "- **#{race[:conference]} race** (current standings; home team sits #{ordinal(race[:home_position])}, " \
              "road team #{ordinal(race[:away_position])}):" ]
    race[:table].each_with_index do |row, index|
      mark = row[:user_coached] ? " [our coach]" : ""
      lines << "  - #{index + 1}. #{row[:name]}#{mark}: #{row[:conference_record][:wins]}-#{row[:conference_record][:losses]} in conference " \
               "(#{row[:overall_record][:wins]}-#{row[:overall_record][:losses]} overall)"
    end
    lines
  end

  def elsewhere_lines(elsewhere)
    return [] if elsewhere.blank?

    lines = [ "- **Elsewhere** (games this week that bear on this one; a quick mention only):" ]
    elsewhere.each { |entry| lines << "  - #{entry[:away]} @ #{entry[:home]}: #{entry[:reason]}" }
    lines
  end

  def ordinal(number)
    return "unplaced" unless number

    suffix = number.between?(11, 13) ? "th" : { 1 => "st", 2 => "nd", 3 => "rd" }.fetch(number % 10, "th")
    "#{number}#{suffix}"
  end

  # ---- film room ---------------------------------------------------------------

  def film_room_lines(game)
    lines = [ "### 🎞️ THE FILM ROOM", "" ]
    matchups = game[:film_room][:matchups].first(3)
    if matchups.any?
      lines << "**Matchups that decide it** (biggest edge first):"
      matchups.each { |matchup| lines << "- #{matchup_text(matchup)}" }
      lines << ""
    end

    [ game[:away], game[:home] ].each { |team| lines.concat(key_player_lines(team)) }
    lines.concat(injury_lines(game))
    lines
  end

  def matchup_text(matchup)
    edge = matchup[:edge]
    leader = edge.positive? ? matchup[:offense] : matchup[:defense]
    size = edge.abs >= 10 ? "a huge edge" : edge.abs >= 5 ? "a clear edge" : "a slight edge"
    "#{matchup[:offense]}'s #{matchup[:label].sub('vs. the', 'against the')} (#{matchup[:defense]}): #{size} for #{leader} " \
      "(backstage: #{matchup[:offense_rating]} vs. #{matchup[:defense_rating]})"
  end

  def key_player_lines(team)
    players = team[:key_players][:offense] + team[:key_players][:defense]
    return [] if players.empty?

    lines = [ "**#{team[:college][:name]} players to watch:**" ]
    players.each { |player| lines << "- #{player_text(player)}" }
    lines << ""
    lines
  end

  def player_text(player)
    dev = player[:dev_trait].present? ? ", #{player[:dev_trait]} dev" : ""
    stats = stat_text(player[:season_stats])
    "#{player[:name]} (#{player[:position]}, #{player[:class_year]}, backstage overall #{player[:overall]}#{dev})#{stats ? " — #{stats}" : ''}"
  end

  def stat_text(stats)
    return nil unless stats

    parts = []
    passing = stats[:passing]
    parts << "#{passing[:completions]}/#{passing[:attempts]}, #{passing[:yards]} yds, #{passing[:tds]} TD, #{passing[:interceptions]} INT" if passing
    rushing = stats[:rushing]
    parts << "#{rushing[:carries]} carries for #{rushing[:yards]} yds (#{rushing[:avg]}), #{rushing[:tds]} TD" if rushing
    receiving = stats[:receiving]
    parts << "#{receiving[:receptions]} catches for #{receiving[:yards]} yds, #{receiving[:tds]} TD" if receiving
    defense = stats[:defense]
    parts << "#{defense[:tackles].to_i} tackles, #{defense[:tfl].to_f} TFL, #{defense[:sacks].to_f} sacks, #{defense[:interceptions].to_i} INT" if defense
    parts.empty? ? nil : "#{parts.join('; ')} in #{stats[:games_played]} #{stats[:games_played] == 1 ? 'game' : 'games'}"
  end

  def injury_lines(game)
    entries = [ game[:away], game[:home] ].flat_map { |team| team[:injuries].map { |injury| [ team[:college][:name], injury ] } }
    return [] if entries.empty?

    lines = [ "**Injuries:**" ]
    entries.each { |name, injury| lines << "- #{name}: #{injury_text(injury)}" }
    lines << ""
    lines
  end

  def injury_text(injury)
    status = { "out_for_season" => "OUT FOR THE SEASON", "out_this_game" => "OUT this week",
               "returning_this_game" => "RETURNING this week" }.fetch(injury[:status])
    role = injury[:starter] ? "starter" : "backup"
    replacement = injury[:replacement] ? "; next up is #{injury[:replacement][:name]} (backstage #{injury[:replacement][:overall]})" : ""
    "#{injury[:name]} (#{injury[:position]}, #{role}, backstage #{injury[:overall]}) — #{injury[:description]}, #{status}#{replacement}"
  end

  # ---- quarterback duel ----------------------------------------------------------

  def quarterback_lines(game)
    away, home = game[:quarterback_duel].values_at(:away, :home)
    return [] unless away && home

    lines = [ "### 🎯 THE QUARTERBACK DUEL", "" ]
    lines << "- **#{game[:away][:college][:name]}:** #{player_text(away)}#{starter_note(away)}"
    lines << "- **#{game[:home][:college][:name]}:** #{player_text(home)}#{starter_note(home)}"
    lines << ""
    lines
  end

  # Shown when the coach starts a quarterback over a higher-rated teammate:
  # a storyline for the hosts, with the rating itself kept backstage.
  def starter_note(quarterback)
    higher = quarterback[:over_higher_rated]
    higher ? " — this is the quarterback actually playing; the coach starts him over higher-rated #{higher[:name]} (backstage #{higher[:overall]})" : ""
  end

  # ---- the pick ----------------------------------------------------------------

  def pick_lines(game)
    return [ "### 💰 THE PICK", "", "No bet was recorded for this game (it has already been played), so skip THE PICK for it.", "" ] if game[:picks].empty?

    lines = [ "### 💰 THE PICK (MANDATORY DIALOGUE BEAT)", "",
              "Before moving on, BOTH hosts must state their exact bet out loud, give one fresh reason, and react to " \
              "the other host's call (thirty to forty-five seconds total):" ]
    game[:picks].each_with_index do |pick, index|
      same_as_first = index.positive? && pick[:bet] == game[:picks].first[:bet]
      lines << "- **#{pick[:host]}'s Call:** \"#{spoken_call(pick, same_as_first)}\""
    end
    lines << "*(Hosts MUST announce their picks out loud for this game before #{pick_transition(game)}.)*"
    lines << ""
    lines
  end

  def pick_transition(game)
    index = games.index(game)
    index == games.size - 1 ? "the Next Episode tease" : "transitioning to Game #{index + 2}"
  end

  # What a host says: "I'm taking Kansas State plus eleven and a half." The
  # favorite is "laying the points"; a second host on the same side picks up
  # on the first ("Same side for me").
  def spoken_call(pick, same_as_first)
    lead = same_as_first ? "Same side for me: " : ""
    number = spoken_number(pick[:number])
    call =
      if pick[:market] == "total"
        "I'm taking the #{pick[:side]} at #{number}."
      elsif pick[:favorite]
        "I'm laying the points with #{pick[:team]} minus #{number}."
      else
        "I'm taking #{pick[:team]} plus #{number}."
      end
    "#{lead}#{call}"
  end

  ONES = %w[zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen
            seventeen eighteen nineteen].freeze
  TENS = %w[_ _ twenty thirty forty fifty sixty seventy eighty ninety].freeze

  # 11.5 -> "eleven and a half", 0.5 -> "a half", 55.5 -> "fifty-five and a half".
  def spoken_number(number)
    whole = number.floor
    remainder = number - whole
    half = (remainder - 0.5).abs < 0.001
    return number.to_s unless whole < 100 && (half || remainder.zero?)

    words = whole < 20 ? ONES[whole] : [ TENS[whole / 10], (ONES[whole % 10] unless (whole % 10).zero?) ].compact.join("-")
    return words unless half

    whole.zero? ? "a half" : "#{words} and a half"
  end

  def also_on
    Array(@data[:also_on])
  end

  def also_on_segment
    "Also on the Board — a quick heads-up on #{also_on.size} other game#{'s' if also_on.size != 1} worth knowing about " \
      "(no picks, no predictions, no analysis)"
  end

  # A short list at the very end for games we have no stake in: the rest of
  # our league and any ranked-vs-ranked game. Information only, so the hosts
  # are told not to bet, predict or analyze.
  def also_on_lines
    return [] if also_on.empty?

    lines = [ "---", "", "## 📋 ALSO ON THE BOARD (HEADS-UP ONLY)", "",
              "A quick heads-up for listeners on other games worth knowing about, after the last pick and before the " \
              "Next Episode tease. These are NOT bets: no picks, no predictions, no analysis and no film room. For each " \
              "game: name it (with rankings), say when and where it's on, and mention the line casually if one is " \
              "listed (\"favored by a field goal\"). About ten seconds a game, then move on.", "" ]
    also_on.each { |entry| lines << also_on_line_text(entry) }
    lines << ""
    lines
  end

  def also_on_line_text(entry)
    tags = []
    tags << "ranked vs. ranked" if entry[:ranked_matchup]
    tags << "#{entry[:conference]} game" if entry[:conference]
    parts = [ tags.join(" · "), (kickoff_text(entry[:time]) if entry[:time]), entry[:broadcast], line_note(entry[:line]) ].compact_blank
    "- #{also_on_team_text(entry[:away])} @ #{also_on_team_text(entry[:home])} — #{parts.join(' · ')}"
  end

  def also_on_team_text(team)
    record = "#{team[:record][:wins]}-#{team[:record][:losses]}"
    "#{team[:ranking] ? "No. #{team[:ranking]} " : ''}#{team[:name]} (#{record})"
  end

  def line_note(line)
    line ? "Line: #{line[:favorite]} -#{line[:spread]}, total #{line[:total]}" : nil
  end

  def next_episode_segment
    "Next Episode — tease the Week #{@data.dig(:week, :number)} reactions episode#{next_episode_when} " \
      "(no recap of the picks)"
  end

  # " on Monday, September 13", or " later this week" with no date on file.
  def next_episode_when
    review = @data.dig(:podcast_date, :review_date)
    review ? " on #{Date.parse(review).strftime('%A, %B %-d')}" : " later this week"
  end

  # The close of the show. Each pick was already said out loud at the end of
  # its game, so there's deliberately no recap of the bets here.
  def next_episode_lines
    week = @data.dig(:week, :number)

    [ "---", "", "## 👋 NEXT EPISODE — WEEK #{week} REACTIONS", "",
      "End the show by telling listeners to catch the Week #{week} reactions episode#{next_episode_when}, where we " \
      "react to how these games played out. The bets are already on the record, so do not recap or re-read them, " \
      "and don't predict anything further. Just the tease.", "" ]
  end
end
