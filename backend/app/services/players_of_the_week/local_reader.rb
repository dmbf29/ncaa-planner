require "open3"

module PlayersOfTheWeek
  # Reads Player of the Week screenshots on this Mac with Apple Vision (tools/capture/read_potw.py) instead of asking
  # the AI, and returns the same hash as Extractor. Each screenshot is read on its own: one whose scope, week, names,
  # positions or results can't all be read is handed to the AI instead, so the result mixes the two as needed. The
  # winner's team is found the same way as before, from the opponent and score (GameCollegeResolver); one it can't
  # find stays unmatched for the review screen. Last names are printed in capitals, so a name already on that
  # team's roster keeps its spelling and any other is capitalised and flagged as not yet on the roster.
  class LocalReader
    SCRIPT = ScheduleStats::LocalSchedule::SCRIPT
    PYTHON = ScheduleStats::LocalSchedule::PYTHON
    TIMEOUT = 120

    def self.available?
      ScheduleStats::LocalSchedule.available?
    end

    # images: the uploaded files (anything with a #tempfile).
    def call(images, season:)
      images = Array(images)
      extractor = Extractor.new
      readings = self.class.available? && images.all? { |image| image.respond_to?(:tempfile) } ? read(images.map { |image| image.tempfile.path }) : []
      matcher = ScheduleStats::LocalSchedule.new

      rows, fallback = [], []
      images.each_with_index do |image, index|
        local = build_rows(readings[index], season, extractor, matcher)
        local ? rows.concat(local) : fallback << image
      end
      ai = fallback.any? ? extractor.call(fallback, season: season) : { groups: [] }

      { groups: extractor.group_rows(rows) + ai[:groups], colleges: matcher.send(:colleges_json), warnings: rows.filter_map { |row| row.delete(:warning) } }
    end

    private

    def read(paths)
      Dir.mktmpdir("local_potw") do |dir|
        jobs_path = File.join(dir, "jobs.json")
        File.write(jobs_path, paths.map { |path| { file: path.to_s, kind: "potw" } }.to_json)
        stdout, _stderr, status = Timeout.timeout(TIMEOUT) { Open3.capture3(PYTHON, SCRIPT.to_s, jobs_path) }
        return [] unless status.success?

        JSON.parse(stdout).map { |entry| entry["result"] unless entry["result"].is_a?(Hash) && entry["result"]["error"] }
      end
    rescue Timeout::Error, JSON::ParserError, Errno::ENOENT
      []
    end

    # nil when this screenshot wasn't read completely.
    def build_rows(reading, season, extractor, matcher)
      return nil unless reading.is_a?(Hash) && reading["scope"].present? && reading["week"].present?

      cards = Array(reading["cards"])
      return nil unless cards.size == 2 && cards.map { |card| card["side"] }.sort == %w[defensive offensive]
      return nil unless cards.all? { |card| %w[first last pos opponent result team_score opponent_score].all? { |key| card[key].present? } && card["stat_lines"].present? }

      week = extractor.resolve_week(season, reading["week"])
      resolver = GameCollegeResolver.new(week) if week
      national = reading["scope"].strip.casecmp?("national")

      cards.map { |card| build_row(card, reading, week, resolver, national, matcher) }
    end

    def build_row(card, reading, week, resolver, national, matcher)
      opponent = matcher.match_college(card["opponent"])
      # The screen prints the winning score first, whoever's team it is.
      winning, losing = [ card["team_score"], card["opponent_score"] ].minmax.reverse
      won = card["result"] == "W"
      college = resolver&.resolve(opponent_raw_name: opponent&.name, opponent_matched_name: nil,
                                  team_score: won ? winning : losing, opponent_score: won ? losing : winning)
      last_name = roster_spelling(college, card["first"], card["last"])

      { week_id: week&.id, week_label: reading["week"], national: national, conference: national ? nil : reading["scope"].strip,
        side: card["side"], first_name: card["first"], last_name: last_name, position: card["pos"],
        stat_line: card["stat_lines"].join(", "), college_id: college&.id,
        opponent_context: "#{card['venue']} #{card['opponent']} (#{card['result']} #{card['team_score']}-#{card['opponent_score']})",
        class_year: nil, warning: (roster_warning(college, card["first"], last_name) if college) }
    end

    def roster_spelling(college, first, printed_last)
      known = roster_names(college).find { |name| name.casecmp?("#{first} #{printed_last}") } if college
      known ? known.delete_prefix("#{first} ") : printed_last.split(/([ \-'])/).map(&:capitalize).join
    end

    def roster_warning(college, first, last)
      "#{first} #{last} (#{college.name}) isn't on that team's roster yet — check the spelling." unless roster_names(college).include?("#{first} #{last}")
    end

    def roster_names(college)
      (@roster_names ||= {})[college.id] ||= Student.joins(student_seasons: :college_season).where(college_seasons: { college_id: college.id }).distinct.map(&:name)
    end
  end
end
