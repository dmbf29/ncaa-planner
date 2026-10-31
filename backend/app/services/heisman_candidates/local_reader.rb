require "open3"

module HeismanCandidates
  # Reads a Heisman Watch List screenshot on this Mac with Apple Vision (tools/capture/read_heisman.py) instead of
  # asking the AI, and returns the same hash as Extractor. Returns nil when it can't settle every row (a team that
  # matches no college, an unrecognisable position or year, nothing readable), so the caller sends the upload to the
  # AI instead. A name that isn't on that college's roster yet is only a warning: the player may be new to the list.
  class LocalReader
    SCRIPT = ScheduleStats::LocalSchedule::SCRIPT
    PYTHON = ScheduleStats::LocalSchedule::PYTHON
    TIMEOUT = 120
    POSITIONS = %w[QB HB FB WR TE LT LG C RG RT OT OL DT DE EDGE LB MLB OLB CB S FS SS K P LS ATH].freeze
    CLASS_YEAR = /\A(FR|SO|JR|SR)(\(RS\))?\z/

    def self.available?
      ScheduleStats::LocalSchedule.available?
    end

    # paths: the screenshots' files on disk.
    def call(paths)
      return nil unless self.class.available?

      matcher = ScheduleStats::LocalSchedule.new
      readings = read_rows(paths)
      rows = readings.filter_map { |reading| build_row(reading, matcher) }.uniq { |row| [ row[:first_name], row[:last_name], row[:college_id] ] }
      return nil if rows.empty? || rows.size < readings.uniq { |r| r["name"] }.size

      { rows: rows, colleges: matcher.send(:colleges_json), warnings: rows.filter_map { |row| row.delete(:warning) } }
    rescue Timeout::Error, JSON::ParserError, Errno::ENOENT
      nil
    end

    private

    def read_rows(paths)
      Dir.mktmpdir("local_heisman") do |dir|
        jobs_path = File.join(dir, "jobs.json")
        File.write(jobs_path, paths.map { |path| { file: path.to_s, kind: "heisman" } }.to_json)
        stdout, _stderr, status = Timeout.timeout(TIMEOUT) { Open3.capture3(PYTHON, SCRIPT.to_s, jobs_path) }
        return [] unless status.success?

        JSON.parse(stdout).flat_map do |entry|
          result = entry["result"]
          result.is_a?(Hash) && !result["error"] ? Array(result["rows"]) : []
        end
      end
    end

    def build_row(reading, matcher)
      college = matcher.match_college(reading["team"])
      position = reading["pos"].to_s.upcase
      class_year = reading["year"].to_s.upcase.gsub(/\s+/, "")
      first_name, last_name = reading["name"].to_s.split(" ", 2)
      return nil unless college && POSITIONS.include?(position) && class_year.match?(CLASS_YEAR) && last_name.present?

      { first_name: first_name, last_name: last_name, position: position, college_raw_name: reading["team"],
        college_id: college.id, class_year: class_year, warning: roster_warning(college, "#{first_name} #{last_name}") }
    end

    def roster_warning(college, full_name)
      known = Student.joins(student_seasons: :college_season).where(college_seasons: { college_id: college.id }).distinct.any? { |s| s.name.casecmp?(full_name) }
      "#{full_name} (#{college.name}) isn't on that team's roster yet — check the spelling." unless known
    end
  end
end
