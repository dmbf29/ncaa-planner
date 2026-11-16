module Discord
  # One Discord post per game with its highlights and full-game videos, hiding the score in a spoiler. It is posted when the
  # first video is uploaded (the other one reads "Coming soon") and edited (games.discord_message_id) when the other one arrives. Safe to call after every upload.
  class GameVideoPost
    LINES = { "highlights" => "🎬 Highlights", "full" => "📺 Full game" }.freeze

    def self.message(game)
      week = game.week
      videos = game.game_videos.select { |video| video.provider == "youtube" }.group_by(&:kind).transform_values(&:first)
      away = game.away_college.name
      home = game.home_college.name
      scores = game.college_game_stats.to_h { |stat| [ stat.college_id, stat.final_score ] }
      matchup = "**#{away} at #{home}**"
      matchup += " ||#{away} #{scores[game.away_college_id]}, #{home} #{scores[game.home_college_id]}||" if scores.values_at(game.away_college_id, game.home_college_id).all?

      links = LINES.map { |kind, label| "#{label}: #{videos[kind] ? "https://youtu.be/#{videos[kind].source}" : "Coming soon"}" }
      [ "#{week.season.year} season · #{week.name || "Week #{week.number}"}", matchup, *links ].join("\n")
    end

    def initialize(game, webhook: Webhook.new)
      @game = game
      @webhook = webhook
    end

    # Posts, or edits the earlier post. Returns false if skipped (no webhook, or no YouTube video yet).
    def call
      return false unless Webhook.configured? && ready?

      content = self.class.message(@game)
      if @game.discord_message_id
        begin
          @webhook.edit(@game.discord_message_id, content)
          return true
        rescue Webhook::NotFound
          # The post was deleted in Discord; fall through and post it again.
        end
      end
      @game.update_columns(discord_message_id: @webhook.post(content))
      true
    end

    def ready?
      @game.game_videos.any? { |video| video.provider == "youtube" }
    end
  end
end
