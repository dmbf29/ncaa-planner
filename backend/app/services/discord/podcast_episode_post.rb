module Discord
  # Announces a newly published podcast episode. It first links the show, because Spotify assigns the episode's own link only
  # after it picks the episode up from the RSS feed a few minutes later; PodcastEpisodeLinkJob then edits the post (episode_url:).
  class PodcastEpisodePost
    SPOTIFY_SHOW_URL = "https://open.spotify.com/show/#{Spotify::Episodes::SHOW_ID}".freeze

    def self.message(title:, season:, episode:, episode_url: nil)
      [ "🎙️ New episode of #{Podcast::Show::TITLE}",
        "**#{title}**",
        "Season #{season}, Episode #{episode}",
        "🎧 Listen on Spotify: #{episode_url || SPOTIFY_SHOW_URL}",
        ("-# It can take a few minutes to show up." unless episode_url) ].compact.join("\n")
    end

    def initialize(title:, season:, episode:, webhook: Webhook.new)
      @args = { title: title, season: season, episode: episode }
      @webhook = webhook
    end

    # Posts the announcement and returns the Discord message id, or nil when no webhook is configured.
    def call
      return unless Webhook.configured?

      @webhook.post(self.class.message(**@args))
    end

    # Replaces the show link with the episode's own link.
    def link_episode(message_id, episode_url)
      @webhook.edit(message_id, self.class.message(**@args, episode_url: episode_url))
    end
  end
end
