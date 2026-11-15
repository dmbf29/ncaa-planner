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
    params = URI.decode_www_form(URI(request_line.split[1].to_s, nil).query.to_s).to_h
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
end
