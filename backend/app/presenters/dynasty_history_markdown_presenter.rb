# Renders DynastyHistorySerializer's hash as the "league history" source document the podcast writers get alongside an
# episode's own document. The all-time tallies come first and are phrased as facts the hosts can lean on ("the Sun Belt
# has had one Heisman winner"), so a repeat is never mistaken for a first. Empty string when there is no history yet.
class DynastyHistoryMarkdownPresenter
  # Seasons whose chronicle is shown in full; older ones keep only its first paragraph, so the document stays short.
  FULL_CHRONICLE_SEASONS = 2

  def initialize(data)
    @data = data
    @conference = data[:our_conference]
  end

  def to_markdown
    return "" if @data[:seasons].empty?

    lines = [ "# LEAGUE HISTORY THROUGH THE #{@data[:through_year]} SEASON", "" ]
    lines << "> Producer note (DO NOT READ ALOUD): everything below already happened in earlier seasons. It is established " \
             "background, not news. Use it to give context and a sense of continuity, never as the main story, and never " \
             "present any of it as new, surprising or a first."
    lines << ""
    lines.concat(tally_lines)
    lines.concat(season_lines)
    lines.concat(series_lines)
    lines.join("\n").rstrip + "\n"
  end

  private

  def seasons = @data[:seasons]

  def tally_lines
    lines = [ "## ALL-TIME TALLIES (ESTABLISHED FACTS)", "" ]
    titles = seasons.filter_map { |s| s[:national_champion] && [ s[:year], s[:national_champion][:winner] ] }
    if titles.any?
      lines << "- **National champions:** #{titles.map { |year, team| "#{year} #{team}" }.join(', ')}."
      repeats = titles.map(&:last).tally.select { |_, count| count > 1 }
      lines << "- Multiple national titles: #{repeats.map { |team, count| "#{team} (#{count})" }.join(', ')}." if repeats.any?
    end
    lines.concat(conference_lines)
    lines.concat(award_tally_lines)
    lines << ""
    lines
  end

  def conference_lines
    return [] unless @conference

    own_titles = seasons.flat_map { |s| s[:conference_champions].select { |c| c[:conference] == @conference }.map { |c| [ s[:year], c[:winner] ] } }
    lines = []
    if own_titles.any?
      lines << "- **#{@conference} champions:** #{own_titles.map { |year, team| "#{year} #{team}" }.join(', ')}."
    end
    won = seasons.select { |s| (champion = s.dig(:national_champion, :winner)) && program_conference(s, champion) == @conference }
    if won.any?
      lines << "- **#{@conference} national championships:** #{won.size} (#{won.map { |s| "#{s[:year]} #{s.dig(:national_champion, :winner)}" }.join(', ')})."
    elsif seasons.any? { |s| s[:national_champion] }
      lines << "- No #{@conference} program has won a national championship."
    end
    lines.compact
  end

  def program_conference(season, college_name)
    season[:our_programs].find { |p| p[:college] == college_name }&.fetch(:conference) ||
      season[:conference_champions].find { |c| c[:winner] == college_name }&.fetch(:conference)
  end

  # For every award a #{conference} player or coach has won: how many times, and who. Plus every headline award's
  # winners, so the hosts know whether a winner's conference or school has had one before.
  def award_tally_lines
    wins = seasons.flat_map { |s| s[:awards].map { |a| a.merge(year: s[:year]) } }
    own = wins.select { |a| a[:conference] == @conference }.group_by { |a| a[:award] }
    lines = own.map do |award, rows|
      who = rows.map { |a| "#{a[:year]} #{a[:name]} (#{[ a[:position], a[:college] ].compact.join(', ')})" }.join("; ")
      times = rows.size == 1 ? "once" : "#{rows.size} times"
      "- **#{award}, #{@conference}:** won #{times} so far: #{who}."
    end
    lines
  end

  def season_lines
    seasons.reverse.each_with_index.flat_map do |s, index|
      lines = [ "## #{s[:year]} SEASON", "" ]
      lines.concat(chronicle_lines(s, index))
      if (title = s[:national_champion])
        lines << "- **National champion:** #{title[:winner]}, beating #{title[:loser]} #{title[:winner_score]}-#{title[:loser_score]} in the title game."
      end
      s[:conference_champions].select { |c| c[:conference] == @conference }.each do |c|
        lines << "- **#{c[:conference]} champion:** #{c[:winner]} (beat #{c[:loser]} #{c[:winner_score]}-#{c[:loser_score]} in the title game)."
      end
      s[:awards].each do |a|
        lines << "- **#{a[:award]}:** #{a[:name]} (#{[ a[:position], a[:college], a[:conference] ].compact.join(', ')})."
      end
      unless s[:our_programs].empty?
        lines << "- **Our programs:** #{s[:our_programs].map { |p| program_text(p) }.join('; ')}."
      end
      lines << ""
      lines
    end
  end

  def chronicle_lines(season, index)
    return [] if season[:chronicle].blank?

    paragraphs = season[:chronicle].split(/\n{2,}/).map(&:strip).compact_blank
    paragraphs = paragraphs.first(1) if index >= FULL_CHRONICLE_SEASONS
    [ "**The season's story:** #{paragraphs.join(' ')}", "" ]
  end

  def program_text(program)
    tags = []
    tags << "national champions" if program[:national_champion]
    tags << "conference champions" if program[:conference_champion]
    record = program[:wins] && program[:losses] ? " #{program[:wins]}-#{program[:losses]}" : ""
    "#{program[:college]}#{record} under #{program[:coach]}#{" (#{tags.join(', ')})" if tags.any?}"
  end

  def series_lines
    return [] if @data[:series].empty?

    lines = [ "## SERIES BETWEEN OUR PROGRAMS (all-time in this league, earlier seasons)", "" ]
    @data[:series].each do |row|
      a, b = row[:teams]
      lines << "- #{a} vs #{b}: #{a} #{row[:wins][a]}, #{b} #{row[:wins][b]}."
    end
    lines << ""
  end
end
