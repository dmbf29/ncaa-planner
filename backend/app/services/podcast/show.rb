# Show-level podcast metadata shared by the episode description, artwork and RSS feed.
module Podcast
  module Show
    TITLE = ScriptWriter::SHOW_NAME
    TAGLINE = "A Sun Belt football podcast".freeze
    DESCRIPTION = "Rising in the Sun Belt is a weekly Sun Belt football show. Arlis Boardingham and Ty Simpson " \
                  "break down every result, the standings and the playoff picture, then look ahead to the " \
                  "weekend's biggest games with their picks.".freeze
    AUTHOR = "Arlis Boardingham & Ty Simpson".freeze
    LANGUAGE = "en-us".freeze
    CATEGORY = "Sports".freeze
    # Apple/Spotify want the owner's email in the feed (Spotify emails a verification code to it), and a feed is
    # public, so it only goes in if you set it.
    OWNER_EMAIL = ENV["PODCAST_OWNER_EMAIL"].presence

    # The address podcast apps are given. It is a proxy on douglasberkley.com (see that site's netlify.toml) that
    # serves the feed file from Cloudinary, so the storage behind it can change without touching Spotify.
    FEED_URL = "https://www.douglasberkley.com/podcast/rising-in-the-sun-belt.xml".freeze

    ROOT = File.expand_path("../../../../pod", __dir__)
    FEED_DIR = File.join(ROOT, "feed")
    ART_DIR = File.join(ROOT, "art")
    COVER_SOURCE = File.join(ART_DIR, "rising_in_the_sun_belt.png")
    CLOUD_FOLDER = "rising_in_the_sun_belt".freeze

    # The dynasty season number doubles as the podcast season number (2026 was season 1).
    def self.season_for(year)
      year.to_i - 2025
    end
  end
end
