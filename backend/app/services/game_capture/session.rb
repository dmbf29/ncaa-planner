module GameCapture
  # Local-only: runs tools/capture/watch.py (which screenshots the PS Remote
  # Play window as you navigate the game with a controller) on behalf of one
  # game, then turns what it saved into the same three screenshot buckets
  # GamesController#analyze takes and enqueues the same GameAnalysisJob.
  #
  # State lives in tmp/game_capture_<game_id>.json (pid + output dir) rather
  # than the DB, so a Rails restart mid-capture can still find and stop it.
  # The watcher needs Screen Recording + Accessibility permission for whichever
  # app launched `bin/rails server` (e.g. Terminal) — it inherits them.
  class Session
    REPO_ROOT = Rails.root.join("..").expand_path
    SCRIPT = REPO_ROOT.join("tools/capture/watch.py")
    CAPTURES_DIR = REPO_ROOT.join("pod/captures")
    # Stopping waits for the watcher to finish OCR'ing screens still queued.
    STOP_TIMEOUT = 60

    Error = Class.new(StandardError)

    def initialize(game)
      @game = game
    end

    def start!
      return status if running?

      name = "game-#{@game.id}-#{Time.current.strftime('%Y%m%d-%H%M%S')}"
      dir = CAPTURES_DIR.join(name)
      FileUtils.mkdir_p(dir)

      pid = Process.spawn(
        ENV.fetch("CAPTURE_PYTHON", "python3"), "-u", SCRIPT.to_s,
        "--out", CAPTURES_DIR.to_s, "--name", name,
        "--teams", "#{@game.home_college.name},#{@game.away_college.name}",
        out: dir.join("watcher.log").to_s, err: %i[child out], pgroup: true
      )
      Process.detach(pid)
      write_state(pid: pid, dir: dir.to_s)
      status
    end

    # Points this game at an existing capture folder with no watcher running, so the
    # game page offers "Analyze saved capture" for it. Re-label first if needed
    # (tools/capture/relabel.py).
    def adopt!(dir)
      dir = Pathname.new(dir).expand_path
      raise Error, "#{dir} isn't a capture folder." unless dir.to_s.start_with?(CAPTURES_DIR.to_s) && dir.join("manifest.json").exist?
      raise Error, "A capture is still running for this game." if running?

      write_state(pid: nil, dir: dir.to_s)
      status
    end

    def status
      state = read_state
      return { running: false, screens: [] } unless state

      all = screens(state[:dir])
      { running: alive?(state[:pid]), screens: all.map { |s| s.except(:grafted_from) }, unpaired: unpaired_views(all).map { |s| s.slice(:file, :team, :hscroll) } }
    end

    def running?
      state = read_state
      state.present? && alive?(state[:pid])
    end

    # Stops the watcher (SIGINT makes it finish queued screens first), buckets
    # what it saved, and kicks off the analysis. Returns the analyze_status
    # token plus any team-stats screens it couldn't tie to either team.
    def finish!
      state = read_state or raise Error, "No capture in progress for this game."
      stop_watcher(state[:pid])

      all = screens(state[:dir])
      buckets = bucket(all)
      raise Error, "Nothing was captured yet — navigate to the box score / player stats first." if buckets.values_at(:box_score, :home, :away).all?(&:empty?)

      token = SecureRandom.uuid
      AnalysisStatus.pending!(token)
      GameAnalysisJob.perform_later(
        game_id: @game.id,
        token: token,
        box_score_signed_ids: signed_ids(state[:dir], buckets[:box_score]),
        home_signed_ids: signed_ids(state[:dir], buckets[:home]),
        away_signed_ids: signed_ids(state[:dir], buckets[:away]),
        home_categories: buckets[:home].pluck(:category),
        away_categories: buckets[:away].pluck(:category),
        replace_screenshots: true
      )
      clear_state
      { token: token, unassigned: buckets[:unassigned].map { |s| s[:file] }, unpaired: unpaired_views(all).size, partial_rows: partial_rows(all) }
    end

    def cancel!
      state = read_state
      stop_watcher(state[:pid]) if state
      clear_state
    end

    private

    def bucket(all)
      # Right-scrolled Defense views have no NAME column, so they can't be read on
      # their own; their grafted composite (category "defense_extra") carries them.
      team_stats = all.select { |s| s[:kind] == "team_stats" && s[:hscroll] != "right" }
      {
        box_score: all.select { |s| s[:kind] == "box_score" },
        home: team_stats.select { |s| s[:team] == @game.home_college.name },
        away: team_stats.select { |s| s[:team] == @game.away_college.name },
        unassigned: team_stats.reject { |s| [ @game.home_college.name, @game.away_college.name ].include?(s[:team]) }
      }
    end

    # Defense views (left or right of the scrolling table) with no grafted composite:
    # the list scrolled between the two captures, so they don't show the same rows.
    def unpaired_views(all)
      paired = all.flat_map { |s| Array(s[:grafted_from]) }
      all.select { |s| s[:category] == "defense" && %w[left right].include?(s[:hscroll]) && paired.exclude?(s[:file]) }
    end

    # Rows whose names or right-hand stats were left out because the list scrolled between
    # the left and right captures of a page (only the rows both views show are grafted).
    def partial_rows(all)
      all.select { |s| s[:category] == "defense_extra" && s[:overlap_rows] }.sum { |s| 11 - s[:overlap_rows] }
    end

    def signed_ids(dir, screens)
      screens.map do |screen|
        File.open(File.join(dir, screen[:file])) do |io|
          ActiveStorage::Blob.create_and_upload!(io: io, filename: screen[:file], content_type: "image/png").signed_id
        end
      end
    end

    def screens(dir)
      manifest = File.join(dir.to_s, "manifest.json")
      return [] unless File.exist?(manifest)

      JSON.parse(File.read(manifest)).reject { |entry| entry["ignore"] }.map do |entry|
        entry.slice("file", "kind", "team", "category", "hscroll", "grafted_from", "overlap_rows", "at").symbolize_keys
      end
    rescue JSON::ParserError
      [] # caught mid-write; the next poll will see the full file
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
      Rails.root.join("tmp/game_capture_#{@game.id}.json")
    end

    def read_state
      JSON.parse(File.read(state_path), symbolize_names: true) if File.exist?(state_path)
    end

    def write_state(state)
      File.write(state_path, state.to_json)
    end

    def clear_state
      FileUtils.rm_f(state_path)
    end
  end
end
