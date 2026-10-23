require "json"

# The weekly episode, step by step. The Export page drives these through Podcast::EpisodeStatus and
# PodcastEpisodeJob; `bin/rails "podcast:weekly[YEAR,WEEK]"` drives the same steps from a terminal.
#
#   prepare       recap + preview markdown (from the app's own serializers, the same data the old exports gave),
#                 cover art, script, fact-check. Cheap, and ends with a pause for the human to review.
#   produce       voices and mix, then the description. Costs real money, so it only runs once approved.
#   publish       adds the episode to the feed (uploads when live: true, otherwise a dry run).
#   regenerate_art
#
# Everything lands in pod/episodes/<year>_week-<N>/ and each step skips work whose output is already there, so a
# failed or interrupted run resumes where it stopped.
module Podcast
  class WeeklyRun
    def initialize(year:, week_number:, season_id: nil, episode: nil, live: false, force: false, model: nil, status: nil)
      @year = year.to_i
      @week = week_number.to_i
      @season = season_id.present? ? Season.find(season_id) : Season.where(year: @year).order(:id).last
      raise "No season found for #{@year}" unless @season

      @episode = episode.presence&.to_i
      @live = live
      @model = model
      @status = status || EpisodeStatus.new(year: @year, week_number: @week)
      @dir = @status.dir
      FileUtils.rm_rf(@dir) if force
      FileUtils.mkdir_p(@dir)
    end

    def prepare
      write_markdown
      make_art
      write_script
      fact_check
    end

    def produce(redo_audio: false)
      clear_audio if redo_audio
      produce_audio
      EpisodeInfo.new(script_path: path("script.checked.txt"), year: @year, week_number: @week,
                      preview_week: (@week + 1 if preview?), model: @model).description
    end

    def regenerate_art
      FileUtils.rm_f(art_path)
      make_art
    end

    # Returns the feed address. Raises unless the audio has been produced.
    def publish
      raise "Voices haven't been produced yet" unless File.exist?(path("episode.mp3"))

      log "adding the episode to the feed#{' (dry run)' unless @live}"
      info = description_info
      final = File.join(Show::ROOT, "podcast_audio", format("%<y>d_%<w>02d_episode.mp3", y: @year, w: @week))
      FileUtils.cp(path("episode.mp3"), final)
      Publisher.new(live: @live).publish(
        key: EpisodeStatus.key_for(@year, @week), title: info.title, description: info.description,
        season: Show.season_for(@year), episode: @episode || @status.to_h[:suggested_episode],
        audio_path: final, art_path: art_path
      )
    end

    # The terminal flow: prepare, pause for review unless approved, then produce and publish.
    def call(approve: false)
      prepare
      return pause unless approve

      produce
      result = publish
      puts "#{@live ? 'PUBLISHED' : 'DRY RUN (nothing uploaded)'}: #{description_info.title}\n  Feed: #{result}"
      puts(@live ? "Spotify picks it up from the feed on its own." : "Re-run with CONFIRM=1 to publish for real.")
      :done
    end

    private

    def path(name) = File.join(@dir, name)

    def log(message)
      $stderr.puts("[weekly] #{message}")
      @status.progress!(message)
    end

    def preview? = File.exist?(path("preview.md"))

    def art_path = EpisodeStatus.art_path(@year, @week)

    def description_info
      EpisodeInfo.new(script_path: path("script.checked.txt"), year: @year, week_number: @week,
                      preview_week: (@week + 1 if preview?), model: @model)
    end

    # ---- prepare ---------------------------------------------------------------------

    def write_markdown
      unless File.exist?(path("recap.md"))
        log "Building the Week #{@week} recap from the app's data"
        data = SeasonWeeksSerializer.new(@season, [ @week ]).as_json
        File.write(path("recap.md"), SeasonWeeksMarkdownPresenter.new(data).to_markdown)
      end
      return if File.exist?(path("preview.md")) || File.exist?(path("no_preview"))

      log "Building the Week #{@week + 1} preview (this locks that week's lines and picks, as the old export did)"
      data = BigGameBreakdownSerializer.new(@season, @week + 1, lock: true).as_json
      if data[:games].present?
        File.write(path("preview.md"), BigGameBreakdownMarkdownPresenter.new(data).to_markdown)
      else
        log "No coached team plays in Week #{@week + 1}: this will be a recap-only episode"
        FileUtils.touch(path("no_preview"))
      end
    end

    def make_art
      return if File.exist?(art_path)

      unless preview?
        FileUtils.cp(Show::COVER_SOURCE, art_path) # recap-only: the show cover
        return
      end

      log "Generating the cover art"
      ArtworkGenerator.new(preview_path: path("preview.md"), recap_week: @week, preview_week: @week + 1,
                           out_path: art_path, model: @model).call
    end

    def write_script
      return if File.exist?(path("script.txt"))

      log "Writing the script (about 5 minutes)"
      turns = ScriptWriter.new(markdown_path: path("recap.md"), preview_markdown_path: (path("preview.md") if preview?),
                               year: @year, week_number: @week, model: @model).call
      File.write(path("script.txt"), ScriptWriter.to_text(turns))
    end

    def fact_check
      return if File.exist?(path("script.checked.txt"))

      log "Fact-checking the script (about 6 minutes)"
      turns = File.readlines(path("script.txt"), chomp: true).filter_map do |line|
        match = /\A(ARLIS|TY):\s*(.+)\z/.match(line)
        { speaker: match[1], text: match[2] } if match
      end
      sources = [ path("recap.md"), (path("preview.md") if preview?) ].compact
      checker = FactChecker.new(turns: turns, source_paths: sources, model: @model)
      fixed, corrected = checker.call
      File.write(path("factcheck.md"), FactChecker.report(fixed, turns, checker.needs_review, checker.rejected))
      File.write(path("factcheck.json"), JSON.generate(fixed: fixed.size, needs_review: checker.needs_review.size,
                                                      rejected: checker.rejected.size))
      File.write(path("script.checked.txt"), ScriptWriter.to_text(corrected))
    end

    def pause
      words = File.read(path("script.checked.txt")).split.size
      puts <<~TEXT

        Paused for your review. Nothing has been voiced or published.
          Script (#{words} words, ~#{(words / 189.0).round} min): #{path('script.checked.txt')}
          Fact-check report: #{path('factcheck.md')}
        Read the "Needs your call" section, edit script.checked.txt if you want, then continue with:
          APPROVE=1 bin/rails "podcast:weekly[#{@year},#{@week}]"
        (add CONFIRM=1 to actually publish; without it the run ends with a dry-run feed preview)
      TEXT
      :paused
    end

    # ---- produce ---------------------------------------------------------------------

    def produce_audio
      return if File.exist?(path("episode.mp3"))

      log "Voicing and mixing the episode (about 10 minutes)"
      EpisodeProducer.new(script_path: path("script.checked.txt"), out_dir: @dir, name: "episode").call
      Dir[path("episode_chunk*.wav")].each { |chunk| FileUtils.rm_f(chunk) }
    end

    # After the script was edited: the old voices, mix and description no longer match it.
    def clear_audio
      FileUtils.rm_f(Dir[path("episode*.wav"), path("episode.mp3"), path("script.checked.description.txt")])
    end
  end
end
