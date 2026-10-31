require "open3"

module RankingStats
  # Reads a Top 25 poll captured from Remote Play (Top25Capture::Session) on this Mac with Apple Vision
  # (tools/capture/read_top25.py) instead of asking the AI. Returns the rows the Top 25 review screen shows
  # ({ rank, college_name, college_id, lw_ranking }). Every screenshot shows part of the list and they overlap, so a
  # rank is read several times; the most-agreed reading wins. A rank that was never read, or whose team doesn't match a
  # college, is listed under `warnings` for the review screen instead of being guessed.
  class LocalTop25
    SCRIPT = ScheduleStats::LocalSchedule::SCRIPT
    PYTHON = ScheduleStats::LocalSchedule::PYTHON
    TIMEOUT = 600

    Error = Class.new(StandardError)

    def self.available?
      ScheduleStats::LocalSchedule.available?
    end

    def call(paths)
      raise Error, "The local reader isn't available (needs development mode and the roster-video venv)." unless self.class.available?

      matcher = ScheduleStats::LocalSchedule.new
      readings = read_frames(paths).flat_map { |frame| Array(frame["rows"]) }.group_by { |row| row["rank"] }

      warnings = []
      rows = (1..25).filter_map do |rank|
        candidates = Array(readings[rank])
        if candidates.empty?
          warnings << "##{rank}: never read — scroll slower past it or add it by hand."
          next
        end

        row = build_row(rank, candidates, matcher)
        warnings << "##{rank}: couldn't match \"#{row[:college_name]}\" to a college." if row[:college_id].nil?
        row
      end
      warnings.concat(duplicate_warnings(rows))
      warnings << "No rankings were read from the captured screens." if rows.empty?

      { rows: rows, colleges: matcher.send(:colleges_json), warnings: warnings }
    end

    private

    def build_row(rank, candidates, matcher)
      matched = candidates.filter_map { |c| (college = matcher.match_college(c["name"])) && [ college, c ] }
      college = matched.map(&:first).tally.max_by(&:last)&.first
      name = (matched.find { |c, _| c == college }&.last || candidates.max_by { |c| c["name"].to_s.length })["name"]
      lw = candidates.filter_map { |c| c["lw"] }.tally.max_by(&:last)&.first

      { rank: rank, college_name: name, college_id: college&.id, lw_ranking: lw }
    end

    def duplicate_warnings(rows)
      rows.select(&:itself).group_by { |r| r[:college_id] }.filter_map do |college_id, group|
        "#{group.map { |r| "##{r[:rank]}" }.join(' and ')} matched the same college." if college_id && group.size > 1
      end
    end

    def read_frames(paths)
      Dir.mktmpdir("local_top25") do |dir|
        jobs_path = File.join(dir, "jobs.json")
        File.write(jobs_path, paths.map { |path| { file: path.to_s, kind: "top25" } }.to_json)
        stdout, stderr, status = Timeout.timeout(TIMEOUT) { Open3.capture3(PYTHON, SCRIPT.to_s, jobs_path) }
        raise Error, "The local reader failed: #{stderr.lines.last(3).join.strip.presence || "exit #{status.exitstatus}"}" unless status.success?

        JSON.parse(stdout).filter_map do |entry|
          result = entry["result"]
          result if result.is_a?(Hash) && !result["error"]
        end
      end
    end
  end
end
