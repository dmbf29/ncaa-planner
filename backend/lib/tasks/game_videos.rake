namespace :game_videos do
  desc "Attach a video to a game: rake game_videos:add[GAME_ID,youtube_url_or_id,Optional title]. " \
       "PROVIDER=file with a direct URL instead plays it in a <video> tag. DURATION=<seconds> and TWITCH_VOD=<id> are optional."
  task :add, %i[game_id source title] => :environment do |_task, args|
    game = Game.find(args.fetch(:game_id))
    video = game.game_videos.create!(
      provider: ENV.fetch("PROVIDER", "youtube"),
      source: args.fetch(:source),
      title: args[:title],
      duration_seconds: ENV["DURATION"]&.to_i,
      source_twitch_vod_id: ENV["TWITCH_VOD"]
    )
    puts "Added video #{video.id} (#{video.provider}:#{video.source}) to game #{game.id}: " \
         "#{game.away_college.name} at #{game.home_college.name}, #{game.week.season.year} #{game.week.name || "Week #{game.week.number}"}"
  end

  desc "List games that could take a video: rake game_videos:games[SEASON_ID,WEEK_NUMBER]"
  task :games, %i[season_id week_number] => :environment do |_task, args|
    week = Season.find(args.fetch(:season_id)).weeks.find_by!(number: args.fetch(:week_number))
    week.games.includes(:home_college, :away_college, :game_videos).each do |game|
      puts "#{game.id}\t#{game.away_college.name} at #{game.home_college.name}\t#{game.game_videos.size} video(s)"
    end
  end
end
