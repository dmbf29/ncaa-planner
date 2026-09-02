# End-of-season variant of MidseasonReportCardMarkdownPresenter. Everything
# about how a single team's evidence is rendered — ratings, record, notable
# results, team stats, results log — is inherited as-is; only the framing
# (there's no more "pace," it's a final verdict) and the closing segment
# (no more remaining schedule to improve against, so it's replaced with
# hardware and the actual conference champions) differ. See the override
# points marked in MidseasonReportCardMarkdownPresenter.
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
      "signature win or bad loss, the final team stats, and the final conference standing as evidence. Ends " \
      "with the hardware our program picked up and a look at who actually won each conference versus who the " \
      "numbers favored back in the win-totals show."
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

  def closing_section
    season_awards_section + conference_champions_section
  end

  def season_awards_section
    lines = [ "---", "", "## 🏆 HARDWARE: SEASON AWARDS", "" ]
    awards = @data[:season_awards]

    return lines + [ "- No season awards recorded.", "" ] if awards.blank?

    ours, others = awards.partition { |a| a[:coached_by_us] }
    lines << "**Ours:**"
    lines << ""
    lines.concat(ours.present? ? ours.map { |a| "- #{award_line(a)}" } : [ "- None of our programs picked up hardware this year." ])
    lines << ""

    if others.present?
      lines << "**Around the rest of the country, for context:**"
      lines << ""
      lines.concat(others.map { |a| "- #{award_line(a)}" })
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
