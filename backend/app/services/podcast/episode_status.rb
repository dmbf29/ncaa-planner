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

    def self.dir_for(year, week_number)
      File.join(Show::ROOT, "episodes", "#{year}_week-#{week_number}")
    end

    def self.art_path(year, week_number)
      File.join(Show::ART_DIR, format("%<y>d_%<w>02d_episode.png", y: year, w: week_number))
    end

    def self.key_for(year, week_number)
      "rising-in-the-sun-belt-#{year}-week-#{week_number}"
    end

    def initialize(year:, week_number:)
      @year = year.to_i
      @week = week_number.to_i
      @dir = self.class.dir_for(@year, @week)
    end

    attr_reader :dir

    def path(name) = File.join(@dir, name)

    # ---- the running job ---------------------------------------------------------

    def start_job!(name, message)
      raise AlreadyRunning, "#{current_job[:name]} is already running for week #{@week}" if running?

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
        year: @year, week_number: @week, preview_week: @week + 1,
        job: current_job.slice(:name, :state, :message, :error, :started_at),
        steps: {
          markdown: File.exist?(path(FILES[:markdown])),
          art: File.exist?(self.class.art_path(@year, @week)),
          script: File.exist?(path(FILES[:script])),
          fact_check: File.exist?(path(FILES[:fact_check])),
          audio: File.exist?(path(FILES[:audio])),
          published: published.present?
        },
        audio_stale: audio_stale?,
        recap_only: File.exist?(path("no_preview")),
        script_words: script_words,
        fact_check: fact_check_json,
        title: published&.fetch("title") || cached_title,
        description: published&.fetch("description", nil) || read_text("script.checked.description.txt"),
        season_number: Show.season_for(@year),
        suggested_episode: suggested_episode,
        published: published && published.slice("episode", "season", "title", "published_at"),
        feed_url: Show::FEED_URL
      }
    end

    def script_text = read_text(FILES[:fact_check]) || read_text(FILES[:script])

    def fact_check_report = read_text("factcheck.md")

    def audio_path = path(FILES[:audio])

    def art_file = self.class.art_path(@year, @week)

    private

    def read_text(name)
      File.exist?(path(name)) ? File.read(path(name)) : nil
    end

    # The script was edited after the voices were made.
    def audio_stale?
      return false unless File.exist?(path(FILES[:audio])) && File.exist?(path(FILES[:fact_check]))

      File.mtime(path(FILES[:audio])) < File.mtime(path(FILES[:fact_check]))
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

    def cached_title
      return nil unless File.exist?(path(FILES[:script]))

      EpisodeInfo.new(script_path: path(FILES[:script]), year: @year, week_number: @week,
                      preview_week: (@week + 1 unless File.exist?(path("no_preview")))).title
    end

    def manifest
      file = Publisher::MANIFEST
      File.exist?(file) ? JSON.parse(File.read(file)) : []
    end

    def published_entry
      manifest.find { |entry| entry["key"] == self.class.key_for(@year, @week) }
    end

    # The next episode number in this season's feed.
    def suggested_episode
      season = Show.season_for(@year)
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
