# End-of-season variant of MidseasonReportCardMarkdownPresenter. Most of
# how a single team's evidence is rendered — ratings, record, team stats —
# is inherited as-is; the framing (there's no more "pace," it's a final
# verdict), the full-season results log wording, the Signature
# Wins/Bad Losses evidence (opponent's actual final record instead of a
# preseason lean — see EndOfSeasonReportCardSerializer#notable_results_json),
# the added bowl-game callout, and the closing segment (no more remaining
# schedule to improve against, so it's replaced with hardware and the
# actual conference champions) all differ. See the override points marked
# in MidseasonReportCardMarkdownPresenter.
class EndOfSeasonReportCardMarkdownPresenter < MidseasonReportCardMarkdownPresenter
  private

  def opening_framing_hint
    "how our coached teams' seasons actually ended"
  end

  def episode_header_line
    "# 🎓 END OF SEASON REPORT CARDS — #{show_name} — #{@data[:season][:year]}"
  end

  def producer_note
    "PRODUCER NOTE: Final grades for our coached teams — the season, including the conference championship and " \
      "bowl game where applicable, is complete, and the app never assigns a letter grade, that's entirely on " \
      "the hosts. Use the final record, whether the team beat or missed the preseason Vegas number, any " \
      "signature win or bad loss, the final team stats, the final conference standing, how the bowl game (if " \
      "any) went, and any All-American honorees as evidence. Ends with the hardware our program picked up " \
      "(plus the Heisman, for national context) and a look at who actually won each conference versus who the " \
      "numbers favored back in the win-totals show."
  end

  def grading_rules
    [
      "For every team, BOTH hosts must independently state their own final letter grade (A+ through F) with " \
      "real reasoning. They are not required to agree — a split grade is good radio, not a problem to resolve.",
      "Ground every grade in the evidence below: the final record, whether the team hit the over or the under " \
      "against their preseason Vegas number, any signature win or bad loss, the final team stats (a " \
      "bowl-eligible team played one extra game — their bowl — that a team that missed the postseason didn't, " \
      "so lean on the per-game numbers over raw totals), how the bowl game (if any) went, any All-American " \
      "honorees, and the final conference standing.",
      "A Signature Win/Bad Loss is judged by the opponent's own final record, not a preseason expectation: a " \
      "signature win means beating a team with 8+ wins; a bad loss means losing to a team at or below .500 if " \
      "our own team finished above .500, or losing to a team with an even worse winning percentage than ours " \
      "if we didn't. Either way, a game against another one of our coached teams always counts as a signature " \
      "win or bad loss regardless of that team's record — a friend's team is always a storyline.",
      "Arlis tends to grade on the eye test and the storyline — expectations, drama, signature moments, how " \
      "the season actually ended. Ty tends to grade on the scoreboard and whether the team actually hit their " \
      "preseason number. Let that tension show."
    ]
  end

  def pace_tone_lines
    lines = [ "## 🎰 TONE — NO STATS-SPEAK ON THE FINAL VERDICT (PRODUCER NOTE, DO NOT READ ALOUD)", "" ]
    pace_tone_rules.each { |rule| lines << "- #{rule}" }
    lines << ""
    lines
  end

  def pace_tone_rules
    [
      "When talking about the preseason Vegas number, don't say \"probability,\" \"model,\" or \"algorithm\" — " \
      "say things like \"hit the over,\" \"cashed the under,\" \"blew past the number Vegas had them at,\" or " \
      "\"fell well short of their preseason total.\""
    ]
  end

  def segments
    team_segments = @data[:teams].map { |t| "#{t[:college][:name]} End of Season Report Card" }
    team_segments + [ "Hardware: Season Awards", "Conference Champions: Predicted vs. Actual" ]
  end

  # Same underlying numbers as the midseason "Pace Check" — with the season
  # over, games_played covers the whole schedule and updated_projected_wins
  # collapses to the final win total, so this reframes it as a resolved
  # verdict instead of an in-progress read.
  def pace_section(context)
    return [] unless context

    lines = [ "### 🎯 Final Vegas Verdict", "" ]
    lines << "- Preseason number: #{format_line(context[:preseason_win_total])} wins"
    lines << "- Final record: #{context[:wins_so_far]}-#{context[:games_played] - context[:wins_so_far]}"
    lines << "- #{final_verdict_line(context)}"
    lines << ""
    lines
  end

  def final_verdict_line(context)
    wins = context[:wins_so_far]
    line = context[:preseason_win_total]

    if wins > line
      "Final verdict: HIT THE OVER — #{wins} wins against a #{format_line(line)} line"
    elsif wins < line
      "Final verdict: HIT THE UNDER — #{wins} wins against a #{format_line(line)} line"
    else
      "Final verdict: push, dead on the number"
    end
  end

  def team_section(team)
    super + bowl_games_section(team[:bowl_games]) + all_americans_section(team[:all_americans])
  end

  # Headers trimmed of the "(beat/lost to a team they had no business...)"
  # parenthetical — the criteria are more specific now (see
  # EndOfSeasonReportCardSerializer#notable_results_json) and no longer
  # match that one-line gloss. Midseason keeps its own wording as-is since
  # its simpler pregame-lean definition still fits.
  def notable_results_section(notable)
    return [] if notable.blank?

    lines = []
    if notable[:signature_wins].present?
      lines << "### 🌟 Signature Wins"
      lines << ""
      notable[:signature_wins].each { |g| lines << "- #{notable_result_line(g)}" }
      lines << ""
    end

    if notable[:bad_losses].present?
      lines << "### 💀 Bad Losses"
      lines << ""
      notable[:bad_losses].each { |g| lines << "- #{notable_result_line(g)}" }
      lines << ""
    end
    lines
  end

  # "Signature Win"/"Bad Loss" now reads the opponent's own final record
  # (see EndOfSeasonReportCardSerializer#notable_results_json) instead of
  # the preseason pregame_projection MidseasonReportCardMarkdownPresenter
  # shows — a preseason lean isn't the right evidence once the whole
  # season, including that opponent's, is in the books. A game against
  # another one of our coached teams always lands here regardless of that
  # team's record, since it's always a notable storyline for this group.
  def notable_result_line(game)
    where = game[:home] ? "vs" : "@"
    tags = []
    tags << "fellow coach" if game[:opponent_coached_by_us]
    record = game[:opponent_record]
    tags << "finished #{record[:wins]}-#{record[:losses]}" if record
    tag_note = tags.present? ? " (#{tags.join(', ')})" : ""
    "#{game[:week_label]} #{where} #{game[:opponent][:name]}#{tag_note} (#{game[:score][:team]}-#{game[:score][:opponent]})"
  end

  # Renamed from the inherited "Results So Far" — every game on this list
  # already happened, there's no more season left to qualify it against.
  def played_schedule_section(schedule)
    lines = [ "### 🗓️ Full Season Results", "" ]
    return lines + [ "- No games recorded this season.", "" ] if schedule.blank?

    schedule.each { |g| lines << played_game_line(g) }
    lines << ""
    lines
  end

  def no_stats_message
    "No stats logged"
  end

  def bowl_games_section(bowl_games)
    return [] if bowl_games.blank?

    header = bowl_games.size > 1 ? "Bowl Games" : "Bowl Game"
    lines = [ "### 🏆 #{header}", "" ]
    bowl_games.each { |g| lines << bowl_game_line(g) }
    lines << ""
    lines
  end

  def bowl_game_line(game)
    where = game[:home] ? "vs" : "@"
    outcome = game[:result][:won] ? "W" : "L"
    score = "#{game[:result][:team_score]}-#{game[:result][:opponent_score]}"
    opp_ratings = game[:opponent_ratings]
    opp_summary = opp_ratings ? " (#{opp_ratings[:overall]} OVR)" : ""
    "- #{game[:week_label]}: #{outcome} #{score} #{where} #{game[:opponent][:name]}#{opp_summary}"
  end

  def all_americans_section(all_americans)
    return [] if all_americans.blank?

    lines = [ "### ⭐ All-Americans", "" ]
    all_americans.each { |aa| lines << "- #{aa[:name]} (#{aa[:position]}) — #{honor_label(aa)}" }
    lines << ""
    lines
  end

  def honor_label(all_american)
    scope = all_american[:national] ? "National" : all_american[:conference]
    tier = all_american[:tier] == 1 ? "1st Team" : "2nd Team"
    preseason = all_american[:preseason] ? "Preseason " : ""
    "#{preseason}#{scope} #{tier}"
  end

  def closing_section
    season_awards_section + conference_champions_section
  end

  # @data[:season_awards] already only carries our own programs' awards
  # plus the Heisman (see EndOfSeasonReportCardSerializer#season_awards) —
  # every other national award is left out entirely, not just de-emphasized.
  def season_awards_section
    lines = [ "---", "", "## 🏆 HARDWARE: SEASON AWARDS", "" ]
    awards = @data[:season_awards]

    return lines + [ "- No season awards recorded.", "" ] if awards.blank?

    ours, heisman = awards.partition { |a| a[:coached_by_us] }
    lines << "**Ours:**"
    lines << ""
    lines.concat(ours.present? ? ours.map { |a| "- #{award_line(a)}" } : [ "- None of our programs picked up hardware this year." ])
    lines << ""

    if heisman.present?
      lines << "**The Heisman Trophy, for national context:**"
      lines << ""
      lines.concat(heisman.map { |a| "- #{award_line(a)}" })
      lines << ""
    end

    lines
  end

  def award_line(award)
    stat_line = award[:stat_line].present? ? " (#{award[:stat_line]})" : ""
    college = award[:college] ? ", #{award[:college][:name]}" : ""
    "#{award[:award]}: #{award[:recipient]}#{college}#{stat_line}"
  end

  def conference_champions_section
    lines = [ "---", "", "## 👑 CONFERENCE CHAMPIONS: PREDICTED VS. ACTUAL", "" ]
    champions = @data[:conference_champions]

    return lines + [ "- No conference championship data available.", "" ] if champions.blank?

    champions.each { |c| lines.concat(conference_champion_bullets(c)) }
    lines
  end

  def conference_champion_bullets(champion)
    lines = [ "**#{champion[:conference]}:**" ]
    finalists = champion[:predicted_finalists]
    actual_champion = champion[:actual_champion]
    actual_runner_up = champion[:actual_runner_up]

    if finalists.present?
      lines << "- Predicted finalists (from the win-totals show): #{matchup_line(finalists, 'vs.')}"
    end

    if actual_champion
      result = actual_runner_up ? matchup_line([ actual_champion, actual_runner_up ], "over") : champion_entry_line(actual_champion)
      lines << "- Actual result: #{result}"
      lines << conference_champion_verdict(champion) if finalists.present?
    else
      lines << "- Actual result: not decided (no conference championship game recorded)"
    end

    lines << ""
    lines
  end

  def conference_champion_verdict(champion)
    champion_predicted = champion[:actual_champion_was_predicted_finalist]
    runner_up_predicted = champion[:actual_runner_up_was_predicted_finalist]

    if champion_predicted && runner_up_predicted
      champion[:actual_champion_was_top_pick] ? "- Vegas called the whole final, and the top pick delivered." : "- Vegas called the whole final, just picked the wrong side to win it."
    elsif champion_predicted || runner_up_predicted
      "- Vegas got half the final right — one of these two came out of nowhere."
    else
      "- Total curveball — neither finalist was on Vegas's radar."
    end
  end

  def champion_entry_line(entry)
    note = entry[:coached_by_us] ? " — one of ours!" : ""
    "#{entry[:college][:name]}#{note}"
  end

  # Same idea as champion_entry_line but for a pair (predicted finalists,
  # or actual champion/runner-up) — puts the "one of ours" note once at the
  # end of the whole matchup instead of stapled awkwardly mid-sentence onto
  # whichever name happens to come first.
  def matchup_line(entries, joiner)
    names = entries.map { |e| e[:college][:name] }.join(" #{joiner} ")
    ours = entries.select { |e| e[:coached_by_us] }.map { |e| e[:college][:name] }
    return names if ours.empty?

    "#{names} (#{ours.join(' and ')} — ours)"
  end
end
