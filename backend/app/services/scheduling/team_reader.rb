require "open3"

module Scheduling
  # Reads a coached team's schedule-setup screenshots on this Mac with Apple Vision (tools/capture/read_team_schedule.py)
  # instead of paying for AI vision. Two screenshots cover weeks 0-13 and overlap, so rows are merged by week.
  #
  # Each week comes back as one of:
  #   locked  - padlock + opponent: a fixed game
  #   bye     - padlock + OPEN
  #   option  - opponent but no padlock: the game's suggestion for the week, which stays open for the coach
  #   open    - OPEN, no padlock
  # Home/away is the AT/VS cell when Vision could read it, otherwise "not the team's own stadium" (the stadium most
  # weeks share). Anything unmatched is left for the review screen rather than guessed.
  class TeamReader
    include CollegeMatching

    SCRIPT = Rails.root.join("../tools/capture/read_screens.py").expand_path
    PYTHON = ENV.fetch("ROSTER_VIDEO_PYTHON") { Rails.root.join("tools/roster_video/venv/bin/python").to_s }
    TIMEOUT = 300

    Error = Class.new(StandardError)

    def self.available?
      Rails.env.development? && File.executable?(PYTHON) && SCRIPT.exist?
    end

    def call(paths, season:)
      raise Error, "The local reader isn't available (needs development mode and the roster-video venv)." unless self.class.available?

      frames = read_frames(paths)
      raise Error, "No schedule rows could be read from those screenshots." if frames.all? { |frame| frame["rows"].blank? }

      team_name = frames.filter_map { |frame| frame["team"] }.tally.max_by(&:last)&.first
      by_week = merge_rows(frames)
      home_stadium = by_week.values.filter_map { |row| row["stadium"].presence }.tally.max_by(&:last)&.first
      week_ids = season.weeks.where(number: Rules::WEEK_NUMBERS).pluck(:number, :id).to_h

      rows = Rules::WEEK_NUMBERS.map { |number| build_row(number, week_ids[number], by_week[number], home_stadium) }
      warnings = rows.filter_map { |row| row.delete(:issue) }
      byes = rows.select { |row| row[:state] == "bye" }.map { |row| row[:week_number] }
      if byes.sort != season.schedule_bye_week_numbers.sort
        warnings << "This team's byes (weeks #{byes.join(', ').presence || 'none'}) don't match the byes set for the season " \
                    "(#{season.schedule_bye_week_numbers.sort.join(', ').presence || 'none'})."
      end

      college = resolve_college(team_name)
      { college_id: college&.id, college_raw_name: team_name, rows: rows, colleges: colleges_json, warnings: warnings }
    end

    private

    def read_frames(paths)
      Dir.mktmpdir("team_schedule") do |dir|
        jobs_path = File.join(dir, "jobs.json")
        File.write(jobs_path, paths.map { |path| { file: path.to_s, kind: "team_schedule" } }.to_json)
        stdout, stderr, status = Timeout.timeout(TIMEOUT) { Open3.capture3(PYTHON, "-W", "ignore", SCRIPT.to_s, jobs_path) }
        raise Error, "The local reader failed: #{stderr.lines.last(3).join.strip.presence || "exit #{status.exitstatus}"}" unless status.success?

        JSON.parse(stdout).filter_map do |entry|
          result = entry["result"]
          result if result.is_a?(Hash) && !result["error"]
        end
      end
    end

    # The same week appears on both screenshots; keep the reading with the most information.
    def merge_rows(frames)
      frames.flat_map { |frame| Array(frame["rows"]) }.select { |row| row["week"] }.group_by { |row| row["week"] }.transform_values do |readings|
        readings.max_by { |row| [ row["opponent"].present? || row["open"] ? 1 : 0, row["location"].present? ? 1 : 0, row["locked"] ? 1 : 0 ] }
      end
    end

    def build_row(number, week_id, reading, home_stadium)
      base = { week_number: number, week_id: week_id, state: "open", opponent_college_id: nil, opponent_raw_name: nil, is_away: false }
      return base.merge(issue: "Week #{number} wasn't read from the screenshots — fill it in or upload again.") if reading.nil?
      return base.merge(state: reading["locked"] ? "bye" : "open") if reading["open"]

      opponent = resolve_college(reading["opponent"])
      row = base.merge(
        state: reading["locked"] ? "locked" : "option", opponent_college_id: opponent&.id, opponent_raw_name: reading["opponent"],
        is_away: away?(reading, home_stadium)
      )
      row[:issue] = "Week #{number}: couldn't match “#{reading['opponent']}” to a team." if opponent.nil?
      row
    end

    def away?(reading, home_stadium)
      case reading["location"].to_s.upcase
      when "AT" then true
      when "VS" then false
      else reading["stadium"].present? && home_stadium.present? && reading["stadium"] != home_stadium
      end
    end
  end
end
