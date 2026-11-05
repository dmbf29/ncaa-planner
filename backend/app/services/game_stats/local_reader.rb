require "open3"

module GameStats
  # Reads Remote Play screenshots on this Mac with Apple Vision (tools/capture/read_screens.py) instead of
  # asking the AI: about a second per screen, free. Development-only, like the other local OCR tools.
  #
  # One instance reads a whole analysis' worth of screenshots in a single Python run (starting Python and
  # Vision costs more than reading an image), then hands each blob's raw result to LocalBoxScore /
  # LocalPlayerTable, which turn it into the same rows the AI extractors produce. Anything that goes wrong
  # (tool missing, unreadable image) leaves that blob without a result, and its extractor uses the AI instead.
  class LocalReader
    SCRIPT = Rails.root.join("../tools/capture/read_screens.py").expand_path
    PYTHON = ENV.fetch("ROSTER_VIDEO_PYTHON") { Rails.root.join("tools/roster_video/venv/bin/python").to_s }
    TIMEOUT = 180

    attr_reader :error

    def self.available?
      Rails.env.development? && ENV["LOCAL_READER"] != "0" && File.executable?(PYTHON) && SCRIPT.exist?
    end

    # Reader for nothing: every lookup misses, so callers go straight to the AI.
    def self.none
      new
    end

    def initialize(box_score_blobs: [], table_blobs: [])
      @results = {}
      @cursors = []
      jobs = box_score_blobs.map { |blob| [ blob, "box_score" ] } + table_blobs.map { |blob| [ blob, "table" ] }
      @cursor_files = cursor_files(table_blobs)
      read(jobs) if (jobs.any? || @cursor_files.any?) && self.class.available?
    end

    # What the player card showed while the cursor sat on a row of this team's tables, from the pictures the
    # capture watcher saved (see tools/capture/watch.py): [{ card_name:, position:, number:, numbers: [...] }].
    def cursors(team_name)
      @cursors.select { |entry| entry[:team] == team_name }
    end

    def box_score(blob)
      result_for(blob, "box_score")
    end

    def table(blob)
      result_for(blob, "table")
    end

    # True if the screenshot was read without an error (even when no table was found on it).
    def read?(blob, kind = "table")
      key = [ blob.id, kind ]
      @results.key?(key) && !(@results[key].is_a?(Hash) && @results[key]["error"])
    end

    private

    # The cursor pictures listed in cursor.json next to the captured screens, as [{ path:, team:, category: }].
    def cursor_files(blobs)
      dirs = blobs.filter_map { |blob| original_path(blob) }.map { |path| File.dirname(path) }.uniq
      dirs.flat_map do |dir|
        log = File.join(dir, "cursor.json")
        next [] unless File.file?(log)

        JSON.parse(File.read(log)).filter_map do |entry|
          path = File.join(dir, entry["file"])
          { path: path, team: entry["team"], category: entry["category"] } if File.file?(path)
        end
      rescue JSON::ParserError
        []
      end
    end

    def result_for(blob, kind)
      result = @results[[ blob.id, kind ]]
      result unless result.is_a?(Hash) && result["error"]
    end

    # A capture saved on this Mac records where its screenshot lives (see GameCapture::Session), so there's no need to
    # download it back from storage.
    def original_path(blob)
      path = blob.metadata["local_path"]
      path if path.present? && File.file?(path)
    end

    def read(jobs)
      Dir.mktmpdir("local_reader") do |dir|
        specs = jobs.each_with_index.map do |(blob, kind), index|
          path = original_path(blob) || File.join(dir, "#{index}#{File.extname(blob.filename.to_s).presence || '.png'}")
          File.binwrite(path, blob.download) unless original_path(blob)
          { file: path, kind: kind, key: [ blob.id, kind ] }
        end
        cursor_specs = @cursor_files.map { |entry| { file: entry[:path], kind: "cursor", key: [ :cursor, entry[:path] ] } }
        jobs_path = File.join(dir, "jobs.json")
        File.write(jobs_path, (specs + cursor_specs).map { |spec| spec.slice(:file, :kind) }.to_json)

        stdout, stderr, status = Timeout.timeout(TIMEOUT) { Open3.capture3(PYTHON, SCRIPT.to_s, jobs_path) }
        unless status.success?
          @error = stderr.lines.last(3).join.strip.presence || "exit #{status.exitstatus}"
          Rails.logger.warn("[local reader] failed: #{@error}")
          return
        end
        all_specs = specs + cursor_specs
        JSON.parse(stdout).each_with_index do |entry, index|
          result = entry["result"]
          if result.is_a?(Hash) && result["error"]
            Rails.logger.warn("[local reader] couldn't read #{File.basename(entry['file'])}: #{result['error'].to_s.lines.last&.strip}")
          elsif all_specs[index][:kind] == "cursor"
            source = @cursor_files.find { |cursor| cursor[:path] == all_specs[index][:file] }
            @cursors << { team: source[:team], category: source[:category], card_name: result["card_name"], position: result["position"],
                          number: result["number"], numbers: Array(result["numbers"]) }
          end
          @results[all_specs[index][:key]] = result
        end
      end
    rescue StandardError => e
      @error = "#{e.class}: #{e.message}"
      Rails.logger.warn("[local reader] failed: #{@error}")
      @results = {}
      @cursors = []
    end
  end
end
