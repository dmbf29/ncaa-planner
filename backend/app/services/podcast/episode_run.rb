require "json"

# One podcast episode, step by step: the weekly recap + preview of a week, or one of the season-long shows (see
# EpisodeSpec). The Export page drives these through Podcast::EpisodeStatus and PodcastEpisodeJob;
# `bin/rails "podcast:episode_run[YEAR,SLUG]"` drives the same steps from a terminal.
#
#   make          prepare + produce in one go
#   prepare       source markdown (from the app's own serializers), cover art, script, fact-check. Cheap, and ends
#                 with a pause for the human to review.
#   produce       voices and mix, then the description. Costs real money, so it only runs once approved.
#   publish       adds the episode to the feed (uploads when live: true, otherwise a dry run).
#   regenerate_art
#
# Everything lands in pod/episodes/<year>_<slug>/ and each step skips work whose output is already there, so a
# failed or interrupted run resumes where it stopped.
module Podcast
  class EpisodeRun
    def initialize(spec:, season_id: nil, episode: nil, live: false, force: false, model: nil, status: nil)
      @spec = spec
      @year = spec.year
      @week = spec.week
      @season = season_id.present? ? Season.find(season_id) : Season.where(year: @year).order(:id).last
      raise "No season found for #{@year}" unless @season

      @episode = episode.presence&.to_i
      @live = live
      @model = model
      @status = status || EpisodeStatus.new(spec: spec)
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

    # Everything up to a finished, listenable episode in one go (the Export page's single button). Publishing stays
    # separate: it's the step that goes live.
    def make
      prepare
      produce
    end

    def produce(redo_audio: false)
      clear_audio if redo_audio
      produce_audio
      description_info.description
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
      final = @spec.final_audio_path
      FileUtils.mkdir_p(File.dirname(final))
      FileUtils.cp(path("episode.mp3"), final)
      Publisher.new(live: @live).publish(
        key: @spec.key, title: info.title, description: info.description,
        season: Show.season_for(@year), episode: @episode || @status.to_h[:suggested_episode],
        audio_path: final, art_path: art_path, preview_weeks: (@spec.preview_weeks || [] if @spec.weekly?),
        previewed_game_ids: (previewed_game_ids if @spec.weekly?)
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

    def preview? = @spec.weekly? && File.exist?(path("preview.md"))

    # An episode with nothing new to preview but a scoreboard of the hosts' bets (see PreviewWeek).
    def scoreboard? = @spec.weekly? && File.exist?(path("scoreboard.md"))

    def art_path = @spec.art_path

    # The ids of the games this episode's preview covered (none for a recap-only or scoreboard-only episode).
    def previewed_game_ids
      file = path("previewed_game_ids.json")
      File.exist?(file) ? JSON.parse(File.read(file)) : []
    end

    def description_info
      EpisodeInfo.new(script_path: path("script.checked.txt"), spec: @spec, recap_only: @spec.weekly? && !preview?, model: @model)
    end

    # ---- prepare ---------------------------------------------------------------------

    def write_markdown
      write_history
      return write_show_markdown unless @spec.weekly?

      unless File.exist?(path("recap.md"))
        log "Building the Week #{@week} recap from the app's data"
        data = SeasonWeeksSerializer.new(@season, [ @week ]).as_json
        File.write(path("recap.md"), SeasonWeeksMarkdownPresenter.new(data).to_markdown)
      end
      return if File.exist?(path("preview.md")) || File.exist?(path("scoreboard.md")) || File.exist?(path("no_preview"))
      return write_scoreboard if @spec.scoreboard_only?

      if @spec.preview_week.nil?
        log "None of our coached teams plays again: this will be a recap-only episode"
        return FileUtils.touch(path("no_preview"))
      end

      log "Building the #{@spec.preview_label} preview (this locks those games' lines and picks, as the old export did)"
      data = merged_preview_data
      if data[:games].present?
        File.write(path("preview.md"), BigGameBreakdownMarkdownPresenter.new(data).to_markdown)
      else
        log "No coached team plays in #{@spec.preview_label}: this will be a recap-only episode"
        FileUtils.touch(path("no_preview"))
      end
    end

    # The league's earlier seasons as background for the hosts (see DynastyHistorySerializer). A weekly episode only gets
    # seasons before this one; an offseason show also gets this season once its national title game has been played.
    def write_history
      return if File.exist?(path("history.md"))

      include_current = !@spec.weekly? && EpisodeSpec.champion_of(@season.weeks.find_by(number: 19)).present?
      write_chronicles(include_current)
      markdown = DynastyHistoryMarkdownPresenter.new(DynastyHistorySerializer.new(@season, include_current: include_current).as_json).to_markdown
      log "Building the league history (#{markdown.empty? ? 'no earlier seasons yet' : "through #{include_current ? @year : @year - 1}"})"
      File.write(path("history.md"), markdown)
    end

    # Each finished season in the history gets its chronicle written the first time an episode needs it. A failure only
    # costs that season its storylines (the facts still go in), so it never blocks the episode.
    def write_chronicles(include_current)
      seasons = DynastyHistorySerializer.new(@season, include_current: include_current).seasons
      seasons.select { |season| season.chronicle.blank? && EpisodeSpec.champion_of(season.weeks.find_by(number: 19)).present? }.each do |season|
        log "Writing the #{season.year} season chronicle"
        SeasonChronicle::Writer.new(season, model: @model).call
      rescue StandardError => e
        log "Couldn't write the #{season.year} chronicle (#{e.message}); continuing without it"
      end
    end

    def history_path = (path("history.md") if File.size?(path("history.md")))

    # Everything still to be played was already previewed in an earlier episode, so this one has no preview. It keeps
    # the scoreboard of the hosts' bets on the week just recapped, read (never locked) from the next week's preview data.
    def write_scoreboard
      log "Everything left to play was already previewed: this episode recaps the week and grades the hosts' bets"
      data = BigGameBreakdownSerializer.new(@season, @spec.scoreboard_week, lock: false).as_json
      markdown = BigGameBreakdownMarkdownPresenter.new(data).scoreboard_markdown
      return FileUtils.touch(path("no_preview")) if markdown.blank?

      File.write(path("scoreboard.md"), markdown)
    end

    # One Big Game Breakdown document for everything previewed. Usually that's a single week; for the postseason it is
    # every bowl week with one of our games, concatenated in the order they're played (the first week supplies the
    # scoreboard of last week's bets and the show header). allow_played_picks: the preview is written as if the games
    # hadn't happened yet, even if they already have.
    def merged_preview_data
      datas = @spec.preview_weeks.map do |number|
        BigGameBreakdownSerializer.new(@season, number, lock: true, allow_played_picks: true,
                                                        exclude_game_ids: @spec.previewed_game_ids).as_json
      end
      # What this episode previews, remembered with the episode when it is published so later ones skip these games.
      File.write(path("previewed_game_ids.json"), JSON.generate(datas.flat_map { |data| data[:games].pluck(:id) }))
      return datas.first if datas.size == 1

      also_on = datas.flat_map { |data| data[:also_on] }.uniq.first(BigGameBreakdownSerializer::ALSO_ON_LIMIT)
      datas.first.merge(games: datas.flat_map { |data| data[:games] }, also_on: also_on)
    end

    # The season-long shows: one document from the app's own serializer and presenter, the same as the old export.
    def write_show_markdown
      return if File.exist?(path("recap.md"))

      log "Building the #{@spec.title} source from the app's data"
      show = @spec.show
      data = show[:serializer].constantize.new(@season).as_json
      File.write(path("recap.md"), show[:presenter].constantize.new(data).to_markdown)
    end

    def make_art
      return if File.exist?(art_path)

      unless @spec.weekly?
        log "Generating the cover art"
        return ShowArtworkGenerator.new(markdown_path: path("recap.md"), spec: @spec, out_path: art_path, model: @model).call
      end

      if @spec.championship?
        log "Generating the national champions cover"
        return ChampionshipArtworkGenerator.new(champion: @spec.champion, year: @year, out_path: art_path).call
      end

      unless preview?
        FileUtils.cp(Show::COVER_SOURCE, art_path) # recap-only: the show cover
        return
      end

      log "Generating the cover art"
      ArtworkGenerator.new(preview_path: path("preview.md"), recap_week: @week, preview_week: @spec.preview_week,
                           preview_label: @spec.preview_label, recap_label: @spec.recap_label, out_path: art_path, model: @model).call
    end

    def write_script
      return if File.exist?(path("script.txt"))

      log "Writing the script (about 5 minutes)"
      writer = if @spec.weekly?
        ScriptWriter.new(markdown_path: path("recap.md"),
                         preview_markdown_path: (path("preview.md") if preview?) || (path("scoreboard.md") if scoreboard?),
                         history_path: history_path,
                         scoreboard_only: scoreboard?, postseason_recap: @spec.recap_postseason, postseason_preview: @spec.preview_postseason,
                         championship: @spec.championship?,
                         year: @year, week_number: @week, recap_label: @spec.recap_label,
                         preview_label: @spec.preview_label, model: @model)
      else
        ShowScriptWriter.new(markdown_path: path("recap.md"), spec: @spec, history_path: history_path, model: @model)
      end
      turns = writer.call
      File.write(path("script.txt"), ScriptWriter.to_text(turns))
    end

    def fact_check
      return if File.exist?(path("script.checked.txt"))

      log "Fact-checking the script (about 6 minutes)"
      turns = File.readlines(path("script.txt"), chomp: true).filter_map do |line|
        match = /\A(ARLIS|TY):\s*(.+)\z/.match(line)
        { speaker: match[1], text: match[2] } if match
      end
      sources = [ path("recap.md"), (path("preview.md") if preview?), (path("scoreboard.md") if scoreboard?), history_path ].compact
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
          APPROVE=1 bin/rails "podcast:episode_run[#{@year},#{@spec.slug}]"
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
