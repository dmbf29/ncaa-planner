require "google/apis/youtube_v3"

module Youtube
  # Uploads a video file to YouTube as unlisted and records it on the game as a GameVideo.
  # Note: until the API project passes YouTube's compliance audit, YouTube forces API uploads
  # to private; the video id is still saved and the video can be set to unlisted in YouTube Studio.
  class Uploader
    def initialize(game, path, title: nil, twitch_vod_id: nil, kind: "full", description: nil)
      @game = game
      @path = path
      @title = title.presence || default_title
      @twitch_vod_id = twitch_vod_id
      @kind = kind
      @description = description
    end

    def call
      raise ArgumentError, "No such file: #{@path}" unless File.file?(@path)

      service = Google::Apis::YoutubeV3::YouTubeService.new
      service.authorization = Credentials.authorized_client
      video = Google::Apis::YoutubeV3::Video.new(
        snippet: Google::Apis::YoutubeV3::VideoSnippet.new(title: @title, description: description, category_id: "20"),
        status: Google::Apis::YoutubeV3::VideoStatus.new(privacy_status: "unlisted", self_declared_made_for_kids: false)
      )
      uploaded = service.insert_video("snippet,status", video, upload_source: @path, content_type: "video/*")

      @game.game_videos.create!(provider: "youtube", source: uploaded.id, title: @title, kind: @kind, source_twitch_vod_id: @twitch_vod_id)
    end

    private

    def default_title
      week = @game.week
      "#{@game.away_college.name} at #{@game.home_college.name} - #{week.season.year} #{week.name || "Week #{week.number}"}#{" Highlights" if @kind == "highlights"}"
    end

    def description
      return @description if @description

      "#{@game.away_college.name} at #{@game.home_college.name}, #{@game.week.season.year} dynasty season."
    end
  end
end
