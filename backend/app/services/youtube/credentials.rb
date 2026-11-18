require "googleauth"

module Youtube
  # OAuth plumbing for the one YouTube channel games are uploaded to. The client id and secret
  # come from a Google Cloud "Desktop app" OAuth client; the refresh token is issued once by
  # `rake youtube:authorize` and lets the uploader get fresh access tokens without signing in.
  module Credentials
    # Full channel access (upload + editing titles/descriptions of videos the app uploaded); a refresh token issued
    # with only youtube.upload can't rename videos, so re-run `rake youtube:authorize` after widening this.
    SCOPE = "https://www.googleapis.com/auth/youtube".freeze
    AUTH_URI = "https://accounts.google.com/o/oauth2/v2/auth".freeze
    TOKEN_URI = "https://oauth2.googleapis.com/token".freeze

    module_function

    def client(redirect_uri: nil, refresh_token: nil)
      Signet::OAuth2::Client.new(
        authorization_uri: AUTH_URI,
        token_credential_uri: TOKEN_URI,
        client_id: ENV.fetch("YOUTUBE_CLIENT_ID"),
        client_secret: ENV.fetch("YOUTUBE_CLIENT_SECRET"),
        scope: SCOPE,
        redirect_uri: redirect_uri,
        refresh_token: refresh_token
      )
    end

    # A client that can already upload; raises KeyError naming the missing env var.
    def authorized_client
      client(refresh_token: ENV.fetch("YOUTUBE_REFRESH_TOKEN")).tap(&:fetch_access_token!)
    end
  end
end
