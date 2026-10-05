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
    "Each host has exactly one bet per game, already decided and listed under THE PICK. Take that side and sell " \
    "it. Say the number out loud the way a bettor would (\"Marshall minus seventeen and a half,\" \"the Over at " \
    "fifty-five and a half\"), and never switch a side or hedge. When both hosts have the same side, it's a " \
    "love-fest; when they split, it's a fight. Never reveal that the bets were handed out.",
    "After the last game, run THE BETTING SLIP: every game, both hosts' bet, one line per game, ten seconds each, " \
    "no new reasoning and no re-arguing. Then give each host's season record from THE SCOREBOARD (if there is one) " \
    "and tease the Review show on the date shown, where these bets get graded.",
    "Mention games elsewhere only when they're listed under \"Elsewhere\" for a game, and only as a quick note on " \
    "how they bear on this one. Don't preview other games, and never run a segment on games we don't have a stake in.",
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
    lines.concat(betting_slip_lines) if games.any?

    lines.join("\n")
  end

  private

  def games
    @data[:games]
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
    list = [ "The Card — set the stakes for the week" ]
    list << "The Scoreboard — each host's season record on their bets so far" if season_record.present?
    games.each_with_index do |game, index|
      list << "Game #{index + 1}: #{matchup_title(game)} — Stakes, Film Room, Quarterback Duel, The Pick"
    end
    list << "The Betting Slip — every pick, one line each" if games.any?
    list
  end

  def matchup_title(game)
    "#{game[:away][:college][:name]} @ #{game[:home][:college][:name]}"
  end

  def date_lines
    info = @data[:podcast_date]
    return [] if info.blank?

    pretty = Date.parse(info[:date]).strftime("%A, %B %-d, %Y")
    lines = [ "**Broadcast date:** #{pretty}, ahead of Week #{info[:week_number]}'s games. Anchor every \"when\" " \
              "reference (\"tomorrow night\", \"this Saturday\") to this date." ]
    if info[:review_date]
      review = Date.parse(info[:review_date]).strftime("%A, %B %-d")
      lines << "**Next show:** the Review show airs #{review}, where these bets get graded."
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

  def scoreboard_lines
    return [] if season_record.blank?

    lines = [ "## 📊 THE SCOREBOARD (season record on bets so far)", "" ]
    season_record.each { |host, record| lines << "- **#{host}:** #{record_text(record)}" }
    last_week = @data.dig(:pick_ledger, :last_week)
    if last_week.present?
      lines << ""
      lines << "Last week's bets:"
      last_week.each do |game|
        picks = game[:picks].map { |pick| "#{pick[:host]} #{pick[:bet]} (#{pick[:result] || 'not played'})" }.join("; ")
        lines << "- #{game[:away]} @ #{game[:home]}: #{picks}"
      end
    end
    lines << ""
    lines
  end

  def record_text(record)
    base = "#{record[:wins]}-#{record[:losses]}"
    record[:pushes].to_i.positive? ? "#{base}-#{record[:pushes]}" : base
  end

  # ---- a game ------------------------------------------------------------------

  def game_section(game, index)
    lines = [ "---", "" ]
    lines << "## 🏈 GAME #{index + 1} OF #{games.size}: #{matchup_title(game)}#{' — THE FINALE' if index == games.size - 1}"
    lines << "**Kickoff:** #{kickoff_text(game[:time])}" if game[:time]
    lines << "**Matchup type:** #{matchup_type(game)}"
    lines.concat(line_lines(game))
    lines.concat(stakes_lines(game))
    lines.concat(film_room_lines(game))
    lines.concat(quarterback_lines(game))
    lines.concat(pick_lines(game))
    lines
  end

  def kickoff_text(time)
    Time.iso8601(time).strftime("%a %b %-d, %-I:%M %p ET")
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
      ""
    ]
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
    record = team[:record]
    lines = [ "- **#{name}**#{coach}: #{record[:wins]}-#{record[:losses]}, #{rank}#{conference_record_text(team)}#{streak_text(team[:streak])}" ]
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

  def conference_record_text(team)
    record = team[:conference_record]
    return "" if record[:wins].zero? && record[:losses].zero?

    " (#{record[:wins]}-#{record[:losses]} in conference)"
  end

  def streak_text(streak)
    return "" unless streak && streak[:length] >= 2

    kind = streak[:kind] == "W" ? "winning" : "losing"
    ", on a #{streak[:length]}-game #{kind} streak"
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
    lines = [ "- **History** (series in this dynasty: #{series}):" ]
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
    parts.empty? ? nil : "#{parts.join('; ')} in #{stats[:games_played]} games"
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
    lines << "- **#{game[:away][:college][:name]}:** #{player_text(away)}"
    lines << "- **#{game[:home][:college][:name]}:** #{player_text(home)}"
    lines << ""
    lines
  end

  # ---- the pick ----------------------------------------------------------------

  def pick_lines(game)
    lines = [ "### 💰 THE PICK", "" ]
    if game[:picks].empty?
      lines << "No bet was recorded for this game (it has already been played), so skip THE PICK for it."
    else
      game[:picks].each { |pick| lines << "- **#{pick[:host]}:** #{pick[:bet]}" }
    end
    lines << ""
    lines
  end

  def betting_slip_lines
    lines = [ "---", "", "## 🧾 THE BETTING SLIP", "", "One line per game, both hosts' bet. No new reasoning.", "" ]
    games.each do |game|
      next if game[:picks].empty?

      bets = game[:picks].map { |pick| "#{pick[:host]}: #{pick[:bet]}" }.join(" · ")
      lines << "- #{matchup_title(game)} — #{bets}"
    end
    lines << ""
    lines
  end
end
