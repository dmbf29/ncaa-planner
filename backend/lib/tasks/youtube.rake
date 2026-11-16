require "socket"
require "securerandom"
require "uri"

namespace :youtube do
  desc "One-time sign-in: opens Google's consent page, catches the redirect on a local port, and prints " \
       "the refresh token to put in backend/.env as YOUTUBE_REFRESH_TOKEN. Needs YOUTUBE_CLIENT_ID and YOUTUBE_CLIENT_SECRET."
  task authorize: :environment do
    server = TCPServer.new("127.0.0.1", 0)
    redirect_uri = "http://127.0.0.1:#{server.addr[1]}"
    state = SecureRandom.hex(16)

    client = Youtube::Credentials.client(redirect_uri: redirect_uri)
    url = client.authorization_uri(
      state: state, access_type: "offline", prompt: "consent", include_granted_scopes: "false"
    ).to_s

    puts "Opening Google's sign-in page. If it doesn't open, paste this URL into your browser:\n\n#{url}\n\n"
    system("open", url) if RUBY_PLATFORM.include?("darwin")

    socket = server.accept
    request_line = socket.gets.to_s
    params = URI.decode_www_form(URI.parse(request_line.split[1].to_s).query.to_s).to_h
    ok = params["state"] == state && params["code"].present?
    socket.print "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n" \
                 "#{ok ? "Done. You can close this tab and return to the terminal." : "Sign-in failed: #{params["error"] || "state mismatch"}"}"
    socket.close
    server.close
    abort "Sign-in failed: #{params["error"] || "state mismatch"}" unless ok

    client.code = params["code"]
    client.fetch_access_token!
    abort "Google returned no refresh token. Remove the app at myaccount.google.com/permissions and run this again." if client.refresh_token.blank?

    puts "Add this line to backend/.env:\n\nYOUTUBE_REFRESH_TOKEN=#{client.refresh_token}\n"
  end

  desc "Upload a video file for a game as unlisted: rake youtube:upload[GAME_ID,/path/to/game.mp4,Optional title]. TWITCH_VOD=<id> is optional."
  task :upload, %i[game_id path title] => :environment do |_task, args|
    game = Game.find(args.fetch(:game_id))
    video = Youtube::Uploader.new(game, File.expand_path(args.fetch(:path)), title: args[:title], twitch_vod_id: ENV["TWITCH_VOD"]).call
    puts "Uploaded https://youtu.be/#{video.source} and attached it to game #{game.id}"
  end

  desc "Upload the stream recording behind every game's scoring summary that has no video yet, oldest week first. " \
       "Recordings are remuxed from .ts to .mp4 (no re-encode) in a temp dir. Re-run it to resume: it stops cleanly " \
       "when YouTube's daily upload quota runs out (about 6 videos on the default quota). DRY_RUN=1 only lists; LIMIT=<n> caps the count."
  task upload_scored: :environment do
    streams = Rails.root.join("..", "streams").expand_path
    games = Game.where.not(scoring_summary: nil).includes(:home_college, :away_college, :game_videos, week: :season)
                .reject { |game| game.game_videos.any? }
                .sort_by { |game| [ game.week.season.year, game.week.number, game.id ] }
    games = games.first(ENV["LIMIT"].to_i) if ENV["LIMIT"].present?

    games.each do |game|
      source = streams.join("#{game.scoring_summary["source"]}.ts")
      label = "#{game.id} #{game.away_college.name} at #{game.home_college.name} (#{game.week.season.year} wk #{game.week.number})"
      unless source.file?
        puts "SKIP #{label}: no recording at #{source}"
        next
      end
      if ENV["DRY_RUN"].present?
        puts "WOULD UPLOAD #{label}: #{source.basename} #{(source.size / 1e9).round(2)} GB"
        next
      end

      Dir.mktmpdir("youtube-upload") do |dir|
        mp4 = File.join(dir, "game.mp4")
        system("ffmpeg", "-v", "error", "-y", "-i", source.to_s, "-c", "copy", "-movflags", "+faststart", mp4) || abort("ffmpeg failed on #{label}")
        video = Youtube::Uploader.new(game, mp4).call
        puts "UPLOADED #{label}: https://youtu.be/#{video.source}"
      end
    rescue Google::Apis::ClientError, Google::Apis::RateLimitError => e
      abort "Stopped at #{label}: #{e.message.lines.first&.strip}. Run again after the quota resets (midnight Pacific)." if e.message.match?(/quota|uploadLimitExceeded/i)
      raise
    end
  end
end

namespace :highlights do
  desc "Cut a highlights video from a game's recording (every scoring play, ~18s before to ~6s after, plus any turnovers " \
       "found by tools/scouting/key_plays.py) into " \
       "streams/highlights/game-<id>.mp4: rake highlights:build[GAME_ID]. UPLOAD=1 also uploads it to YouTube as the game's highlights. " \
       "LEAD=<seconds> and TAIL=<seconds> change the padding around scoring plays; TURNOVERS=0 leaves turnovers out."
  task :build, %i[game_id] => :environment do |_task, args|
    game = Game.includes(:home_college, :away_college, week: :season).find(args.fetch(:game_id))
    output = Highlights::Builder::OUTPUT_DIR.join("game-#{game.id}.mp4")
    builder = Highlights::Builder.new(game, lead: (ENV["LEAD"] || Highlights::Builder::SCORE_PADDING[:lead]).to_f,
                                        tail: (ENV["TAIL"] || Highlights::Builder::SCORE_PADDING[:tail]).to_f, turnovers: ENV["TURNOVERS"] != "0")
    moments = builder.call(output)
    puts "Wrote #{output} (#{(output.size / 1e6).round} MB)"

    if ENV["UPLOAD"].present?
      abort "Game #{game.id} already has a highlights video." if game.game_videos.exists?(kind: "highlights")

      description = Highlights::Builder.description(game, moments)
      video = Youtube::Uploader.new(game, output.to_s, kind: "highlights", description: description).call
      puts "Uploaded https://youtu.be/#{video.source} as the highlights for game #{game.id}"
    end
  end

  desc "Build highlights for every game with a scoring summary and a recording, oldest week first, skipping games whose " \
       "file already exists (FORCE=1 rebuilds). UPLOAD=1 also uploads each one that has no highlights video yet, and stops " \
       "cleanly when YouTube's upload limit is hit (re-run it the next day)."
  task build_scored: :environment do
    games = Game.where.not(scoring_summary: nil).includes(:home_college, :away_college, :game_videos, week: :season)
                .sort_by { |game| [ game.week.season.year, game.week.number, game.id ] }

    games.each do |game|
      label = "#{game.id} #{game.away_college.name} at #{game.home_college.name} (#{game.week.season.year} wk #{game.week.number})"
      output = Highlights::Builder::OUTPUT_DIR.join("game-#{game.id}.mp4")
      moments = nil
      if output.exist? && ENV["FORCE"].blank?
        puts "HAVE #{label}"
      else
        begin
          moments = Highlights::Builder.new(game).call(output)
          puts "BUILT #{label}: #{moments.size} moments, #{(output.size / 1e6).round} MB"
        rescue Highlights::Builder::Error => e
          puts "SKIP #{label}: #{e.message}"
          next
        end
      end
      next if ENV["UPLOAD"].blank? || game.game_videos.any? { |video| video.kind == "highlights" }

      moments ||= Highlights::Builder.new(game).moments_for_description
      description = Highlights::Builder.description(game, moments)
      begin
        video = Youtube::Uploader.new(game, output.to_s, kind: "highlights", description: description).call
        puts "UPLOADED #{label}: https://youtu.be/#{video.source}"
      rescue Google::Apis::ClientError, Google::Apis::RateLimitError => e
        abort "Stopped at #{label}: #{e.message.lines.first&.strip}. Run again after the limit resets." if e.message.match?(/quota|uploadLimitExceeded/i)
        raise
      end
    end
  end
end
