require "open3"

# Runs tools/roster_video/extract.py (local OCR, no AI API) over an uploaded
# screen recording of a roster screen and stores the resulting roster JSON in
# AnalysisStatus for the *_status poller. Development-only: it shells out to a
# Python venv that only exists on the author's machine.
#
# Each run is one subprocess that already uses several cores for OCR, so a
# semaphore caps how many run at once — extra uploads (e.g. several browser
# tabs) wait their turn and report "queued" instead of fighting for CPU.
class RosterVideoJob < ApplicationJob
  queue_as :default

  TOOL_DIR = Rails.root.join("tools/roster_video")
  PYTHON = ENV.fetch("ROSTER_VIDEO_PYTHON") { TOOL_DIR.join("venv/bin/python").to_s }
  UPLOAD_DIR = Rails.root.join("tmp/roster_video")
  MAX_CONCURRENT = Integer(ENV.fetch("ROSTER_VIDEO_CONCURRENCY", 2))
  SLOTS = Concurrent::Semaphore.new(MAX_CONCURRENT)

  def self.stash_upload(token, upload)
    FileUtils.mkdir_p(UPLOAD_DIR)
    path = UPLOAD_DIR.join("#{token}#{File.extname(upload.original_filename.to_s).presence || '.mov'}")
    FileUtils.cp(upload.tempfile.path, path)
    path
  end

  def perform(token:, path:)
    unless File.executable?(PYTHON)
      return AnalysisStatus.failed!(token, "Roster video tool isn't set up — expected a Python env at #{PYTHON} (see tools/roster_video/README.md).")
    end

    AnalysisStatus.progress!(token, { stage: "queued" })
    SLOTS.acquire
    begin
      run_extractor(token, path)
    ensure
      SLOTS.release
    end
  rescue StandardError => e
    AnalysisStatus.failed!(token, "Roster video failed: #{e.message}")
  ensure
    FileUtils.rm_f(path)
  end

  private

  def run_extractor(token, path)
    AnalysisStatus.progress!(token, { stage: "starting" })
    stdout = +""
    stderr_tail = []
    Open3.popen3(PYTHON, TOOL_DIR.join("extract.py").to_s, path) do |stdin, out, err, wait|
      stdin.close
      reader = Thread.new { out.each_line { |line| stdout << line } }
      err.each_line do |line|
        if (m = line.match(/\Aprogress (\d+) (\d+) (\d+)/))
          AnalysisStatus.progress!(token, { stage: "reading", frame: m[1].to_i, total_frames: m[2].to_i, players: m[3].to_i })
        else
          stderr_tail << line.strip
          stderr_tail.shift while stderr_tail.size > 5
        end
      end
      reader.join
      unless wait.value.success?
        return AnalysisStatus.failed!(token, "Extractor exited with an error: #{stderr_tail.last(3).join(' | ')}")
      end
    end

    result = JSON.parse(stdout)
    AnalysisStatus.complete!(token, result.merge("summary" => stderr_tail.last))
  end
end
