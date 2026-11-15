# A recording of a game that league members can watch on the dynasty's Watch page. The host is
# pluggable: "youtube" videos are embedded by id, "file" videos play from a direct URL.
class GameVideo < ApplicationRecord
  PROVIDERS = %w[youtube file].freeze
  YOUTUBE_ID = /\A[\w-]{11}\z/
  YOUTUBE_URL = %r{(?:youtu\.be/|youtube\.com/(?:watch\?(?:.*&)?v=|embed/|live/|shorts/))([\w-]{11})}

  belongs_to :game

  before_validation :normalize_youtube_source

  validates :provider, inclusion: { in: PROVIDERS }
  validates :source, presence: true
  validates :source, format: { with: YOUTUBE_ID, message: "must be a YouTube video id or URL" }, if: -> { provider == "youtube" }
  validates :source, format: { with: %r{\Ahttps?://}, message: "must be an http(s) URL" }, if: -> { provider == "file" }
  validates :source_twitch_vod_id, uniqueness: true, allow_nil: true

  private

  # Accepts a pasted watch/share URL and keeps just the video id.
  def normalize_youtube_source
    return unless provider == "youtube" && source.present?

    self.source = source.strip[YOUTUBE_URL, 1] || source.strip
  end
end
