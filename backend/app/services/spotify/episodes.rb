require "net/http"

module Spotify
  # Looks up an episode of the podcast on Spotify (public data, no user sign-in). Needs SPOTIFY_CLIENT_ID and
  # SPOTIFY_CLIENT_SECRET from a Spotify developer app.
  class Episodes
    Error = Class.new(StandardError)

    SHOW_ID = "0340zOKyJJQSkbgAgBkJ4W".freeze

    def self.configured?
      ENV["SPOTIFY_CLIENT_ID"].present? && ENV["SPOTIFY_CLIENT_SECRET"].present?
    end

    # The open.spotify.com link of the newest episode titled `title`, or nil if Spotify hasn't listed it yet.
    def url_for(title)
      wanted = normalize(title)
      episodes = get("shows/#{SHOW_ID}/episodes", limit: 20, market: "US").fetch("items")
      episodes.find { |episode| normalize(episode["name"]) == wanted }&.dig("external_urls", "spotify")
    end

    private

    def normalize(text)
      text.to_s.squish.downcase
    end

    def get(path, params)
      uri = URI("https://api.spotify.com/v1/#{path}")
      uri.query = URI.encode_www_form(params)
      response = Net::HTTP.get_response(uri, "Authorization" => "Bearer #{token}")
      raise Error, "Spotify returned #{response.code}: #{response.body.to_s.truncate(200)}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end

    def token
      credentials = Base64.strict_encode64("#{ENV.fetch("SPOTIFY_CLIENT_ID")}:#{ENV.fetch("SPOTIFY_CLIENT_SECRET")}")
      response = Net::HTTP.post(URI("https://accounts.spotify.com/api/token"), "grant_type=client_credentials",
                                "Authorization" => "Basic #{credentials}", "Content-Type" => "application/x-www-form-urlencoded")
      raise Error, "Spotify token request returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body).fetch("access_token")
    end
  end
end
