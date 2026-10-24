require "json"

# What the Export page shows about one week's podcast episode: which steps have produced their files (read straight
# from pod/episodes/<year>_week-<N>/, so a retry or a restart never loses track), and which background job, if any,
# is running. The running-job marker is a small status.json in the same folder rather than the cache: the dev cache
# can be a null store, and a job that was running when the server restarted must show as interrupted, not running.
module Podcast
  class EpisodeStatus
    FILES = {
      markdown: "recap.md", script: "script.txt", fact_check: "script.checked.txt", audio: "episode.mp3"
    }.freeze

    def initialize(spec:)
      @spec = spec
      @dir = spec.dir
    end

    attr_reader :dir, :spec

    def path(name) = File.join(@dir, name)

    # ---- the running job ---------------------------------------------------------

    def start_job!(name, message)
      raise AlreadyRunning, "#{current_job[:name]} is already running for this episode" if running?

      FileUtils.mkdir_p(@dir)
      write(name: name, state: "running", message: message, error: nil, started_at: Time.current.iso8601, pid: Process.pid)
    end

    def progress!(message)
      write(read.merge(message: message))
    end

    def finish_job!
      write(read.merge(state: "idle", message: nil, error: nil))
    end

    def fail_job!(error)
      write(read.merge(state: "failed", error: error.to_s))
    end

    def running?
      current_job[:state] == "running"
    end

    # A job marked running by a process that is no longer this one was cut off by a restart.
    def current_job
      job = read
      return { name: nil, state: "idle" } if job.empty?
      return job.merge(state: "interrupted", message: "Interrupted by a server restart: run the step again to resume.") if job[:state] == "running" && job[:pid] != Process.pid

      job
    end

    class AlreadyRunning < StandardError; end

    # ---- what exists on disk -----------------------------------------------------

    def to_h
      published = published_entry
      {
        kind: @spec.kind, slug: @spec.slug, year: @spec.year, week_number: @spec.week, preview_week: @spec.preview_week, preview_label: @spec.preview_label, recap_label: (@spec.recap_label if @spec.weekly?),
        job: current_job.slice(:name, :state, :message, :error, :started_at),
        steps: {
          markdown: File.exist?(path(FILES[:markdown])),
          art: File.exist?(@spec.art_path),
          script: File.exist?(path(FILES[:script])),
          fact_check: File.exist?(path(FILES[:fact_check])),
          audio: File.exist?(path(FILES[:audio])),
          published: published.present?
        },
        audio_stale: audio_stale?,
        recap_only: recap_only?, scoreboard_only: @spec.scoreboard_only?,
        script_words: script_words,
        fact_check: fact_check_json,
        title: published&.fetch("title") || @spec.title(recap_only: recap_only?),
        description: published&.fetch("description", nil) || read_text("script.checked.description.txt"),
        season_number: Show.season_for(@spec.year),
        suggested_episode: suggested_episode,
        published: published && published.slice("episode", "season", "title", "published_at"),
        feed_url: Show::FEED_URL
      }
    end

    def script_text = read_text(FILES[:fact_check]) || read_text(FILES[:script])

    def fact_check_report = read_text("factcheck.md")

    def audio_path = path(FILES[:audio])

    def art_file = @spec.art_path

    # The script was edited after the voices were made.
    def audio_stale?
      return false unless File.exist?(path(FILES[:audio])) && File.exist?(path(FILES[:fact_check]))

      File.mtime(path(FILES[:audio])) < File.mtime(path(FILES[:fact_check]))
    end

    private

    def read_text(name)
      File.exist?(path(name)) ? File.read(path(name)) : nil
    end

    def script_words
      text = script_text
      text && text.split.size
    end

    def fact_check_json
      summary = File.exist?(path("factcheck.json")) ? JSON.parse(File.read(path("factcheck.json")), symbolize_names: true) : nil
      return nil unless summary || fact_check_report

      (summary || {}).merge(report: fact_check_report)
    end

    # A weekly episode with nothing to preview (none of our teams plays again): recap-only.
    def recap_only? = @spec.weekly? && (@spec.preview_week.nil? || File.exist?(path("no_preview")))

    def manifest
      file = Publisher::MANIFEST
      File.exist?(file) ? JSON.parse(File.read(file)) : []
    end

    def published_entry
      manifest.find { |entry| entry["key"] == @spec.key }
    end

    # The next episode number in this season's feed.
    def suggested_episode
      season = Show.season_for(@spec.year)
      manifest.select { |entry| entry["season"] == season }.map { |entry| entry["episode"] }.max.to_i + 1
    end

    def read
      file = path("status.json")
      File.exist?(file) ? JSON.parse(File.read(file), symbolize_names: true) : {}
    rescue JSON::ParserError
      {}
    end

    def write(data)
      FileUtils.mkdir_p(@dir)
      tmp = path("status.json.tmp")
      File.write(tmp, JSON.generate(data.merge(updated_at: Time.current.iso8601)))
      File.rename(tmp, path("status.json"))
    end
  end
end
