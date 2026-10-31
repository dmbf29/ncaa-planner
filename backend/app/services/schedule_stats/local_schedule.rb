require "open3"

module ScheduleStats
  # Reads a week's Scores/Schedules screens captured from Remote Play on this Mac with Apple Vision
  # (tools/capture/read_schedule.py) instead of asking the AI, and returns the same result hash as
  # WeekScheduleExtractor, so the review screen and ScheduleStats::CommitService don't care which one produced it.
  #
  # Each screenshot shows about a dozen rows and the captures overlap, so the same game is read several times. Team
  # names are matched against the colleges' names; a played game's result ("TERPS 34, MICH 32 OT") is printed
  # winner first as two abbreviations, which match the colleges' abbrevs exactly, so they say which side won (and
  # fill in a team whose name was unreadable). Anything that can't be settled is left blank and listed under
  # `warnings` for the review screen rather than guessed.
  class LocalSchedule
    include CollegeMatching

    SCRIPT = Rails.root.join("../tools/capture/read_screens.py").expand_path
    PYTHON = ENV.fetch("ROSTER_VIDEO_PYTHON") { Rails.root.join("tools/roster_video/venv/bin/python").to_s }
    TIMEOUT = 600

    RESULT = /\A\s*([A-Z][A-Z\-.&']*?)\s*(\d+|(?<=\s)O{1,2})\s*,\s*([A-Z][A-Z\-.&']*?)\s*(\d+|(?<=\s)O{1,2})\s*(?:\d?[O0]T)?\s*\z/
    KICKOFF = /\A\s*(\d{1,2}):(\d{2})\s*([AP])M\s*\z/i

    Error = Class.new(StandardError)

    def self.available?
      Rails.env.development? && File.executable?(PYTHON) && SCRIPT.exist?
    end

    # paths: the capture's schedule screenshots, in the order they were taken.
    def call(paths, season: nil)
      raise Error, "The local reader isn't available (needs development mode and the roster-video venv)." unless self.class.available?

      frames = read_frames(paths)
      week_label = frames.filter_map { |frame| normalize_week(frame["week"]) }.tally.max_by(&:last)&.first
      week = WeekLabel.resolve(season, week_label)
      readings = frames.map { |frame| Array(frame["rows"]).filter_map { |row| read_row(row) } }

      merged = merge(readings.flatten(1))
      drop_partial_duplicates(merged)
      drop_clashing_duplicates(merged)
      resolve_conflicts(merged)
      rows = merged.map { |reading| build_row(reading) }
      warnings = rows.filter_map { |row| row.delete(:issue) }
      warnings.concat(conflict_warnings(merged))
      warnings.concat(overlap_warnings(readings))
      warnings << "No games were read from the captured screens." if rows.empty?

      { week_id: week&.id, week_number: week&.number, week_label: week_label, rows: rows, colleges: colleges_json, warnings: warnings }
    end

    private

    def read_frames(paths)
      Dir.mktmpdir("local_schedule") do |dir|
        jobs_path = File.join(dir, "jobs.json")
        File.write(jobs_path, paths.map { |path| { file: path.to_s, kind: "schedule" } }.to_json)
        stdout, stderr, status = Timeout.timeout(TIMEOUT) { Open3.capture3(PYTHON, SCRIPT.to_s, jobs_path) }
        raise Error, "The local reader failed: #{stderr.lines.last(3).join.strip.presence || "exit #{status.exitstatus}"}" unless status.success?

        JSON.parse(stdout).filter_map do |entry|
          result = entry["result"]
          Rails.logger.warn("[local schedule] couldn't read #{File.basename(entry['file'])}: #{result['error'].to_s.lines.last&.strip}") if result.is_a?(Hash) && result["error"]
          result if result.is_a?(Hash) && !result["error"]
        end
      end
    end

    # The header's zero often comes back as the letter O ("WEEK O").
    def normalize_week(label)
      label&.strip&.gsub(/(?<=\s)[O\d]+\z/) { |digits| digits.tr("O", "0") }&.upcase
    end

    # One row of one screenshot -> its teams, date and result as far as they can be read; nil for junk rows
    # (a half-hidden row, the page background).
    def read_row(row)
      result = parse_result(row["result"])
      return nil if result.nil?

      away, home = resolve_sides(match_college(row["away"]), match_college(row["home"]), result)
      return nil if away.nil? && home.nil?

      { away: away, home: home, neutral: row["connector"].to_s.strip.casecmp?("vs"), date: parse_date(row["date"]), result: result,
        raw_away: row["away"], raw_home: row["home"] }
    end

    # The longest college name found in the text, since the logo beside a name often reads as stray letters
    # ("ASO Oklahoma State", "12 UL Monroe") and "Michigan" is inside "Central Michigan".
    def match_college(text)
      return nil if text.blank?

      normalized = canonical(text)
      name_keys.each do |key, college|
        return college if normalized.match?(/(?<![[:alnum:]])#{Regexp.escape(key)}(?![[:alnum:]])/)
      end
      near_match(normalized)
    end

    public :match_college # RankingStats::LocalTop25 matches its team names the same way

    # A name one letter off ("Unio State" for "Ohio State"), once the rank and any logo letters in front are
    # dropped. Only when a single college is that close, and never for short names, where one letter is a different team.
    def near_match(normalized)
      candidates = [ normalized.sub(/\A[^a-z]*/, "") ] + normalized.split.each_index.map { |i| normalized.split.drop(i).join(" ") }
      close = name_keys.select do |key, _college|
        key.length >= 6 && candidates.uniq.any? { |text| DidYouMean::Levenshtein.distance(text, key) <= 1 }
      end.map(&:last).uniq
      close.first if close.size == 1
    end

    # Vision reads the capital I of "Iowa" as a lowercase L, often drops the apostrophe in "Hawai'i" and reads "A&M"
    # as "ASM" or "AM", so both the screen text and the names are compared with i/l merged, apostrophes removed and
    # A&M spelled one way.
    def canonical(text)
      text.downcase.delete("'’").gsub(/\ba[s&5]?m\b/, "a&m").tr("i|1", "l")
    end

    def name_keys
      @name_keys ||= colleges.flat_map { |college| [ college.name, college.alternate_name ].compact_blank.map { |key| [ canonical(key), college ] } }
                             .sort_by { |key, _college| -key.length }
    end

    def parse_result(text)
      text = text.to_s.upcase.strip
      if (kickoff = text.match(KICKOFF))
        return { kind: :scheduled, time: "#{kickoff[1]}:#{kickoff[2]} #{kickoff[3]}M" }
      end

      match = text.match(RESULT)
      return nil unless match

      { kind: :final, first_abbrev: match[1], first_score: to_score(match[2]), second_abbrev: match[3], second_score: to_score(match[4]) }
    end

    def to_score(text)
      text.tr("O", "0").to_i
    end

    def parse_date(text)
      match = text.to_s.match(/([A-Za-z]{3})[a-z]*\.?\s+(\d{1,2})\b/)
      month = match && Date::ABBR_MONTHNAMES.index(match[1].capitalize)
      month ? { month: month, day: match[2].to_i } : nil
    end

    # The same game read from several overlapping screens: keep the reading most screens agree on, preferring one
    # whose result was settled. Games are told apart by their two colleges when both are known, else by raw text.
    def merge(readings)
      readings.group_by { |reading| game_key(reading) }.values.map do |group|
        group.group_by { |reading| [ reading[:result], reading[:date] ] }.max_by { |_value, votes| votes.size }.last.first
              .merge(away: group.filter_map { |r| r[:away] }.first, home: group.filter_map { |r| r[:home] }.first)
      end
    end

    # A game read once with a team's name unreadable and once in full is one game: keep the full reading.
    def drop_partial_duplicates(readings)
      readings.reject! do |reading|
        known = reading[:away] || reading[:home]
        side = reading[:away] ? :away : :home
        (reading[:away].nil? ^ reading[:home].nil?) &&
          readings.any? { |other| !other.equal?(reading) && other[:away] && other[:home] && other[side] == known }
      end
    end

    # The same team on the same side, with the same date and kickoff or result, is one game even if the other team
    # was matched differently ("Texas A&M" read as "Texas" in one frame): keep the reading whose other team's name
    # is the closest fit. Not for an FCS placeholder, which stands in for a different real team each time.
    def drop_clashing_duplicates(readings)
      %i[away home].each do |side|
        other = side == :away ? :home : :away
        readings.group_by { |r| [ r[side]&.id, r[:date], r[:result] ] }.each do |(id, *), group|
          next if id.nil? || group.size < 2 || group.first[side].conference == "FCS"

          best = group.min_by { |r| name_distance(r[:"raw_#{other}"], r[other]) }
          group.each { |r| readings.delete(r) unless r.equal?(best) }
        end
      end
    end

    # A team plays at most once a week (the FCS placeholders stand in for different real teams, so they can repeat).
    # When one shows up in two games, the reading that looks least like its name is probably another college whose
    # name starts the same way ("Texas A&M" read as "AM Texas AGM" matches "Texas"): move it to the college whose
    # name looks most like the text, if that is clearly the best and is either unused or makes this reading a
    # repeat of a game already read (in which case it is dropped).
    def resolve_conflicts(readings)
      sides(readings).group_by { |reading, side| reading[side] }.each do |college, entries|
        next if entries.size < 2

        reading, side = entries.max_by { |r, s| name_distance(r[:"raw_#{s}"], college) }
        raw = reading[:"raw_#{side}"]
        used = readings.flat_map { |r| [ r[:away]&.id, r[:home]&.id ] }
        eligible = colleges.select do |c|
          c != college && canonical(c.name).start_with?(canonical(college.name)) &&
            (used.exclude?(c.id) || repeat_of_another?(readings, reading, side, c))
        end
        ranked = eligible.sort_by { |c| name_distance(raw, c) }
        best = ranked.first
        next unless best && name_distance(raw, best) < name_distance(raw, college)
        next if ranked.size > 1 && name_distance(raw, ranked[1]) - name_distance(raw, best) < 2

        if repeat_of_another?(readings, reading, side, best)
          readings.delete(reading)
        else
          reading[side] = best
        end
      end
    end

    def repeat_of_another?(readings, reading, side, college)
      pair = side == :away ? [ college, reading[:home] ] : [ reading[:away], college ]
      readings.any? { |other| !other.equal?(reading) && [ other[:away], other[:home] ] == pair }
    end

    def conflict_warnings(readings)
      sides(readings).group_by { |reading, side| reading[side] }.filter_map do |college, entries|
        "#{college.name} is in more than one game this week — check the matchups." if entries.size > 1
      end
    end

    def sides(readings)
      readings.flat_map { |reading| %i[away home].map { |side| [ reading, side ] } }
              .select { |reading, side| reading[side] && reading[side].conference != "FCS" }
    end

    def name_distance(raw, college)
      DidYouMean::Levenshtein.distance(canonical(raw.to_s).gsub(/[^a-z0-9]/, ""), canonical(college.name).gsub(/[^a-z0-9]/, ""))
    end

    def game_key(reading)
      ids = [ reading[:away], reading[:home] ].compact.map(&:id)
      ids.size == 2 ? ids.sort : [ reading[:raw_away], reading[:raw_home] ]
    end

    def build_row(reading)
      away, home = reading.values_at(:away, :home)
      scores = resolve_scores(reading[:result], away, home)
      issue = row_issue(reading, away, home, scores)
      date = reading[:date]

      {
        bowl_name: nil,
        away_raw_name: reading[:raw_away],
        away_college_id: away&.id,
        home_raw_name: reading[:raw_home],
        home_college_id: home&.id,
        month: date&.dig(:month),
        day: date&.dig(:day),
        time_of_day: reading[:result][:time],
        away_score: scores[:away],
        home_score: scores[:home],
        issue: issue
      }
    end

    # A played game's two abbreviations are exact, so they correct a name that was misread as a different college
    # ("Texas A&M" read as "AM Texas ASM" matches "Texas") and fill in a team whose name couldn't be read at all.
    # Which side is away comes from the names, so at least one name has to have matched.
    def resolve_sides(away, home, result)
      return [ away, home ] unless result[:kind] == :final

      teams = [ abbrev_college(result[:first_abbrev]), abbrev_college(result[:second_abbrev]) ].compact.uniq
      return [ away, home ] unless teams.size == 2
      return [ away, home ] if teams.include?(away) && teams.include?(home)
      return [ away, (teams - [ away ]).first ] if teams.include?(away)
      return [ (teams - [ home ]).first, home ] if teams.include?(home)

      [ away, home ]
    end

    def resolve_scores(result, away, home)
      return {} unless result[:kind] == :final && away && home

      first = abbrev_for(result[:first_abbrev], [ away, home ])
      second = abbrev_for(result[:second_abbrev], [ away, home ])
      first ||= [ away, home ].find { |c| c != second } if second
      return {} unless first

      first == away ? { away: result[:first_score], home: result[:second_score] } : { away: result[:second_score], home: result[:first_score] }
    end

    # The candidate whose abbrev this is, allowing one misread character ("CLEM7" is fine, "MRSH" for "MRSH").
    def abbrev_for(token, candidates)
      candidates.find { |c| c.abbrev.to_s.casecmp?(token) } ||
        candidates.find { |c| DidYouMean::Levenshtein.distance(c.abbrev.to_s.upcase, token.to_s.upcase) <= 1 }
    end

    def abbrev_college(token)
      colleges.find { |c| c.abbrev.to_s.casecmp?(token) }
    end

    def row_issue(reading, away, home, scores)
      label = "#{reading[:raw_away]} at #{reading[:raw_home]}"
      return "#{label}: couldn't tell which teams these are." unless away && home
      return "#{label}: couldn't match the final score to the teams." if reading[:result][:kind] == :final && scores.empty?

      nil
    end

    # Consecutive screens should share at least one game; if they don't, the list scrolled past some rows.
    def overlap_warnings(readings)
      keyed = readings.map { |frame| frame.map { |reading| game_key(reading) } }.reject(&:empty?)
      keyed.each_cons(2).filter_map do |previous, current|
        "Two captured screens share no games, so some games in between may be missing — scroll more slowly." if (previous & current).empty?
      end.uniq
    end
  end
end
