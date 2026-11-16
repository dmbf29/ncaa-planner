namespace :discord do
  desc "Post to Discord every game that has a YouTube video and hasn't been posted yet, " \
       "oldest week first. DRY_RUN=1 prints the messages instead; LIMIT=<n> caps the count. Needs DISCORD_WEBHOOK_URL."
  task post_game_videos: :environment do
    abort "DISCORD_WEBHOOK_URL is not set." if ENV["DRY_RUN"].blank? && !Discord::Webhook.configured?

    games = Game.where(discord_message_id: nil).includes(:home_college, :away_college, :game_videos, :college_game_stats, week: :season)
                .select { |game| Discord::GameVideoPost.new(game).ready? }
                .sort_by { |game| [ game.week.season.year, game.week.number, game.id ] }
    games = games.first(ENV["LIMIT"].to_i) if ENV["LIMIT"].present?

    games.each do |game|
      if ENV["DRY_RUN"].present?
        puts "--- game #{game.id}", Discord::GameVideoPost.message(game)
      else
        Discord::GameVideoPost.new(game).call
        puts "POSTED game #{game.id}"
        sleep 1
      end
    end
    puts "#{games.size} game(s)#{" (dry run)" if ENV["DRY_RUN"].present?}"
  end
end
