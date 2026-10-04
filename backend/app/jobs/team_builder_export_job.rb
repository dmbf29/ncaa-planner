require "open3"

# Runs tools/team_builder_csv/video_to_csv.py over a recording of a team's roster table (scrolled right across every
# column, then down a page, repeated) and stores the resulting Team Builder Unleashed CSV in AnalysisStatus for the
# *_status poller. Development-only, like RosterVideoJob: it shells out to the same local Python env.
#
# The team's roster is dumped from the DB first so the script can use full first names from there. Nothing is
# written back to the dynasty.
class TeamBuilderExportJob < ApplicationJob
  queue_as :default

  TOOL_DIR = Rails.root.join("tools/team_builder_csv")
  WORK_DIR = Rails.root.join("tmp/team_builder_export")
  # One at a time: a run keeps several cores busy for a few minutes and writes ~600 MB of frames.
  SLOTS = Concurrent::Semaphore.new(1)

  def perform(token:, path:, college_season_id:)
    unless File.executable?(RosterVideoJob::PYTHON)
      return AnalysisStatus.failed!(token, "Python env missing at #{RosterVideoJob::PYTHON} (see tools/roster_video/README.md).")
    end

    college_season = CollegeSeason.find(college_season_id)
    work = WORK_DIR.join(token)
    FileUtils.mkdir_p(work)
    AnalysisStatus.progress!(token, { stage: "queued" })
    SLOTS.acquire
    begin
      File.write(work.join("db_roster.json"), roster_json(college_season))
      run_tool(token, path, work, college_season)
    ensure
      SLOTS.release
    end
  rescue StandardError => e
    AnalysisStatus.failed!(token, "Team Builder export failed: #{e.message}")
  ensure
    FileUtils.rm_f(path)
    FileUtils.rm_rf(work) if work
  end

  private

  def roster_json(college_season)
    players = college_season.student_seasons.includes(:student).map do |ss|
      { first_name: ss.student.first_name, last_name: ss.student.last_name, position: ss.position,
        class_year: ss.class_year, overall: ss.overall }
    end
    { college: college_season.college.name, players: players }.to_json
  end

  def run_tool(token, path, work, college_season)
    AnalysisStatus.progress!(token, { stage: "starting" })
    stderr_tail = []
    Open3.popen3(RosterVideoJob::PYTHON, TOOL_DIR.join("video_to_csv.py").to_s, path, work.to_s) do |stdin, out, err, wait|
      stdin.close
      reader = Thread.new { out.read }
      err.each_line do |line|
        if (m = line.match(/\Aprogress (scan|read|pane) (\d+) (\d+)/))
          AnalysisStatus.progress!(token, { stage: { "scan" => "scanning", "read" => "reading", "pane" => "players" }[m[1]], done: m[2].to_i, total: m[3].to_i })
        else
          stderr_tail << line.strip
          stderr_tail.shift while stderr_tail.size > 5
        end
      end
      reader.join
      unless wait.value.success?
        return AnalysisStatus.failed!(token, "Export tool exited with an error: #{stderr_tail.last(3).join(' | ')}")
      end
    end

    players = JSON.parse(File.read(work.join("players.json")))["players"]
    AnalysisStatus.complete!(token, {
      "csv" => File.read(work.join("team_builder.csv")),
      "filename" => "#{college_season.college.name.parameterize}-team-builder.csv",
      "player_count" => players.size,
      "flagged" => players.select { |p| p["flags"].any? }.map { |p| "#{p['first']} #{p['last']}: #{p['flags'].join('; ')}" },
      "summary" => stderr_tail.last
    })
  end
end
