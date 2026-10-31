module ScheduleCapture
  # Local-only: runs tools/capture/watch.py (which screenshots the PS Remote Play window as you scroll the weekly
  # schedule with a controller) on behalf of one season, and just keeps what it saves in pod/captures/. Nothing is
  # read or analyzed yet; this is for recording real schedule screens to build the local reader against.
  #
  # State lives in tmp/schedule_capture_<season_id>.json (pid + output dir) so a Rails restart mid-capture can
  # still find and stop the watcher.
  class Session
    REPO_ROOT = Rails.root.join("..").expand_path
    SCRIPT = REPO_ROOT.join("tools/capture/watch.py")
    CAPTURES_DIR = REPO_ROOT.join("pod/captures")
    STOP_TIMEOUT = 60
    SIGNATURE_BOX = "0.03,0.30,0.73,0.88".freeze

    def initialize(season)
      @season = season
    end

    def start!
      return status if running?

      name = "schedule-#{@season.year}-#{Time.current.strftime('%Y%m%d-%H%M%S')}"
      dir = CAPTURES_DIR.join(name)
      FileUtils.mkdir_p(dir)

      pid = Process.spawn(
        ENV.fetch("CAPTURE_PYTHON", "python3"), "-u", SCRIPT.to_s, "--out", CAPTURES_DIR.to_s, "--name", name,
        # Watch only the game list: the red animated background and the side panel never hold still. Scrolling a
        # row at a time leaves the page 90% identical, so only a near-exact text match counts as a repeat. Holding the
        # stick scrolls without ever stopping, so a frame is also taken every half second.
        "--signature-box", SIGNATURE_BOX, "--dup", "0.995", "--every", "0.5",
        out: dir.join("watcher.log").to_s, err: %i[child out], pgroup: true
      )
      Process.detach(pid)
      File.write(state_path, { pid: pid, dir: dir.to_s }.to_json)
      status
    end

    def status
      state = read_state
      return { running: false, dir: nil, screens: [] } unless state

      { running: alive?(state[:pid]), dir: state[:dir], screens: screens(state[:dir]) }
    end

    def running?
      state = read_state
      state.present? && alive?(state[:pid])
    end

    # Stops the watcher (SIGINT makes it finish queued screens first) and returns what it saved, plus `paths`: the
    # Scores/Schedules screenshots to read.
    def stop!
      state = read_state
      stop_watcher(state[:pid]) if state
      result = status.merge(paths: schedule_paths(state&.dig(:dir)))
      FileUtils.rm_f(state_path)
      result
    end

    private

    def screens(dir)
      manifest = File.join(dir.to_s, "manifest.json")
      return [] unless File.exist?(manifest)

      JSON.parse(File.read(manifest)).reject { |entry| entry["ignore"] }.pluck("file")
    rescue JSON::ParserError
      [] # caught mid-write; the next poll will see the full file
    end

    def schedule_paths(dir)
      manifest = File.join(dir.to_s, "manifest.json")
      return [] unless File.exist?(manifest)

      JSON.parse(File.read(manifest)).select { |entry| entry["kind"] == "schedule" && !entry["ignore"] }.map { |entry| File.join(dir, entry["file"]) }
    rescue JSON::ParserError
      []
    end

    def stop_watcher(pid)
      return unless alive?(pid)

      Process.kill("INT", pid)
      deadline = Time.current + STOP_TIMEOUT
      sleep 0.5 while alive?(pid) && Time.current < deadline
      Process.kill("KILL", pid) if alive?(pid)
    rescue Errno::ESRCH
      nil
    end

    def alive?(pid)
      return false unless pid.to_i.positive?

      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    end

    def state_path
      Rails.root.join("tmp/schedule_capture_#{@season.id}.json")
    end

    def read_state
      JSON.parse(File.read(state_path), symbolize_names: true) if File.exist?(state_path)
    end
  end
end
