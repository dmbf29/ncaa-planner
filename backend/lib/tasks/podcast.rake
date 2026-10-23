namespace :podcast do
  desc "Write a two-host dialogue script from an exported weekly-review Markdown file into pod/scripts/: " \
       "rake podcast:script[../pod/markdown/2027_week-11-recap.md,2027,11,../pod/markdown/2027_week-12-preview.md]. " \
       "The optional 4th argument adds the next week's Big Game Breakdown preview as the second half of one combined " \
       "episode. MODEL=<id> overrides the model."
  task :script, %i[markdown_path year week_number preview_path] => :environment do |_task, args|
    path = File.expand_path(args.fetch(:markdown_path), Dir.pwd)
    abort "No such file: #{path}" unless File.exist?(path)
    preview_path = args[:preview_path].presence && File.expand_path(args[:preview_path], Dir.pwd)
    abort "No such file: #{preview_path}" if preview_path && !File.exist?(preview_path)

    turns = Podcast::ScriptWriter.new(
      markdown_path: path,
      preview_markdown_path: preview_path,
      year: args.fetch(:year),
      week_number: args.fetch(:week_number),
      model: ENV["MODEL"]
    ).call

    out_dir = Rails.root.join("..", "pod", "scripts").cleanpath
    FileUtils.mkdir_p(out_dir)
    base = preview_path ? "#{args.fetch(:year)}_week-#{args.fetch(:week_number)}-episode" : File.basename(path, ".md")
    out_path = out_dir.join("#{base}.txt")
    File.write(out_path, Podcast::ScriptWriter.to_text(turns))

    words = turns.sum { |turn| turn[:text].split.size }
    puts "Wrote #{out_path}"
    puts "#{turns.size} turns, #{words} words (~#{(words / 189.0).round} min at Gemini's ~189 wpm)"
    puts "Turns by speaker: #{turns.group_by { |turn| turn[:speaker] }.transform_values(&:size)}"
  end

  desc "Fact-check a script against its Markdown sources: rake podcast:fact_check[../pod/scripts/2027_week-11-episode.txt," \
       "../pod/markdown/2027_week-11-recap.md,../pod/markdown/2027_week-12-preview.md]. Writes <name>.factcheck.md " \
       "(the report) and <name>.checked.txt (the script with only the hard number/team/player/line fixes applied; " \
       "judgment calls are reported for you to decide) next to the script. MODEL=<id> overrides the model."
  task :fact_check, %i[script_path source_one source_two] => :environment do |_task, args|
    script_path = File.expand_path(args.fetch(:script_path), Dir.pwd)
    source_paths = [ args[:source_one], args[:source_two] ].compact_blank.map { |path| File.expand_path(path, Dir.pwd) }
    abort "Give at least one source Markdown file" if source_paths.empty?

    turns = File.readlines(script_path, chomp: true).filter_map do |line|
      match = /\A(ARLIS|TY):\s*(.+)\z/.match(line)
      { speaker: match[1], text: match[2] } if match
    end

    checker = Podcast::FactChecker.new(turns: turns, source_paths: source_paths, model: ENV["MODEL"])
    issues, corrected = checker.call

    base = script_path.delete_suffix(".txt")
    File.write("#{base}.factcheck.md", Podcast::FactChecker.report(issues, turns, checker.needs_review, checker.rejected))
    File.write("#{base}.checked.txt", Podcast::ScriptWriter.to_text(corrected))
    puts "#{issues.size} fixed automatically, #{checker.needs_review.size} need your call, " \
         "#{checker.rejected.size} flagged but rejected, out of #{turns.size} turns. Report: #{base}.factcheck.md"
    puts "Corrected script: #{base}.checked.txt"
    issues.each { |issue| puts "  fixed turn #{issue.turn} [#{issue.type}] #{issue.claim}" }
    checker.needs_review.each { |issue| puts "  REVIEW turn #{issue.turn} [#{issue.type}] #{issue.claim}" }
  end

  desc "Voice a whole script with Gemini and mix it with the intro/outro music into pod/voice_tests/<name>.mp3: " \
       "rake podcast:episode[../pod/scripts/2027_week-10-recap.txt]. Voiced chunks are cached, so a rerun resumes. REMIX=1 re-mixes the music only, from the saved speech file."
  task :episode, %i[script_path] => :environment do |_task, args|
    path = File.expand_path(args.fetch(:script_path), Dir.pwd)
    output = Podcast::EpisodeProducer.new(
      script_path: path,
      out_dir: Rails.root.join("..", "pod", "voice_tests").cleanpath.to_s,
      name: File.basename(path, ".txt")
    ).call(remix: ENV["REMIX"] == "1")
    puts "Wrote #{output}"
  end

  desc "Voice the first ~WORDS words (default 450, about 3 minutes) of a script with ElevenLabs and Gemini into " \
       "pod/voice_tests/: rake podcast:voice_test[../pod/scripts/2027_week-10-recap.txt]. ONLY=elevenlabs|gemini."
  task :voice_test, %i[script_path] => :environment do |_task, args|
    test = Podcast::VoiceTest.new(
      script_path: File.expand_path(args.fetch(:script_path), Dir.pwd),
      words: ENV.fetch("WORDS", 450).to_i,
      out_dir: Rails.root.join("..", "pod", "voice_tests").cleanpath.to_s
    )
    puts "Excerpt: #{test.turns.size} turns, #{test.turns.sum { |turn| turn[:text].size }} characters"

    %i[elevenlabs gemini].each do |provider|
      next if ENV["ONLY"] && ENV["ONLY"] != provider.to_s

      begin
        puts "#{provider}: #{test.public_send(provider)}"
      rescue StandardError => error
        puts "#{provider} FAILED: #{error.message}"
      end
    end
  end

  desc "Write the episode title and description (Claude) for a script: rake podcast:describe[../pod/scripts/2027_week-11-episode.checked.txt,2027,11,12]"
  task :describe, %i[script_path year week_number preview_week] => :environment do |_task, args|
    info = Podcast::EpisodeInfo.new(script_path: File.expand_path(args.fetch(:script_path), Dir.pwd),
                                    year: args.fetch(:year), week_number: args.fetch(:week_number), preview_week: args[:preview_week].presence)
    puts info.title, "", info.description
  end

  desc "Generate episode cover art with the OpenAI image API into pod/art/<name>.png: " \
       "rake podcast:artwork[../pod/markdown/2027_week-12-preview.md,11,12,2027_11_episode]"
  task :artwork, %i[preview_path recap_week preview_week name] => :environment do |_task, args|
    out = Rails.root.join("..", "pod", "art", "#{args.fetch(:name)}.png").cleanpath.to_s
    Podcast::ArtworkGenerator.new(preview_path: File.expand_path(args.fetch(:preview_path), Dir.pwd),
                                  recap_week: args.fetch(:recap_week), preview_week: args.fetch(:preview_week),
                                  out_path: out, model: ENV["MODEL"]).call
    puts "Wrote #{out} (prompt saved next to it)"
  end

  desc "Add an episode to the podcast feed. DRY RUN unless CONFIRM=1: dry runs write pod/feed/feed.preview.xml with " \
       "placeholder URLs and upload nothing. rake podcast:publish[2027,11,12,EPISODE_NUMBER,../pod/voice_tests/x.mp3," \
       "../pod/art/2027_11_episode.png,../pod/scripts/2027_week-11-episode.checked.txt]"
  task :publish, %i[year week_number preview_week episode audio_path art_path script_path] => :environment do |_task, args|
    info = Podcast::EpisodeInfo.new(script_path: File.expand_path(args.fetch(:script_path), Dir.pwd),
                                    year: args.fetch(:year), week_number: args.fetch(:week_number),
                                    preview_week: args[:preview_week].presence)
    live = ENV["CONFIRM"] == "1"
    result = Podcast::Publisher.new(live: live).publish(
      key: "rising-in-the-sun-belt-#{args.fetch(:year)}-week-#{args.fetch(:week_number)}",
      title: info.title, description: info.description,
      season: Podcast::Show.season_for(args.fetch(:year)), episode: args.fetch(:episode).to_i,
      audio_path: File.expand_path(args.fetch(:audio_path), Dir.pwd), art_path: File.expand_path(args.fetch(:art_path), Dir.pwd)
    )
    puts live ? "LIVE. Feed address: #{result}" : "Dry run, nothing uploaded. Feed preview: #{result}"
  end

  desc "Download every episode's audio and art from the show's existing Spotify RSS feed (already saved at " \
       "pod/feed/backup/spotify_feed.xml) into pod/feed/backup/ and write imported.json. Resumable; changes nothing live."
  task backup_spotify: :environment do
    episodes = Podcast::SpotifyImporter.new.call
    bytes = episodes.sum { |episode| File.size(episode["audio_file"]) }
    puts "#{episodes.size} episodes backed up (#{(bytes / 1e9).round(2)} GB of audio) in pod/feed/backup/"
  end

  desc "Add the old Spotify-hosted episodes (from podcast:backup_spotify) to the new feed, with their original guids, " \
       "leaving out season 2 episodes 23 and 24, which the new combined episode replaces. DRY RUN unless CONFIRM=1."
  task backfill: :environment do
    live = ENV["CONFIRM"] == "1"
    result = Podcast::Publisher.new(live: live).backfill(exclude: [ [ 2, 23 ], [ 2, 24 ] ])
    puts live ? "LIVE. Feed address: #{result}" : "Dry run, nothing uploaded. Feed preview: #{result}"
  end

  desc "Rebuild feed.xml from the saved episode list and re-upload it. DRY RUN unless CONFIRM=1."
  task rebuild_feed: :environment do
    live = ENV["CONFIRM"] == "1"
    result = Podcast::Publisher.new(live: live).rebuild
    puts live ? "LIVE. Feed address: #{result}" : "Dry run, nothing uploaded. Feed preview: #{result}"
  end

  desc "ONE COMMAND for the weekly episode: rake podcast:weekly[2027,12]. Builds the recap (week N) and preview (week N+1) " \
       "markdown from the app, writes and fact-checks the script, then PAUSES for your review. Re-run with APPROVE=1 to " \
       "voice, mix, write the description, make the cover and add the episode to the feed (dry run unless CONFIRM=1). " \
       "Steps already done are skipped. Optional: SEASON_ID, EPISODE (default: next in the season), FORCE=1 (start " \
       "over), MODEL."
  task :weekly, %i[year week_number] => :environment do |_task, args|
    Podcast::WeeklyRun.new(
      year: args.fetch(:year), week_number: args.fetch(:week_number), season_id: ENV["SEASON_ID"],
      episode: ENV["EPISODE"], live: ENV["CONFIRM"] == "1", force: ENV["FORCE"] == "1", model: ENV["MODEL"]
    ).call(approve: ENV["APPROVE"] == "1")
  end
end
