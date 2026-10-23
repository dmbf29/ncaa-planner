require "json"
require "open3"

# Adds a finished episode to the feed. In a dry run (the default) nothing leaves the machine: the feed is written
# to pod/feed/feed.preview.xml with placeholder URLs so it can be inspected and validated. A live run uploads the
# mp3, the episode art and the show cover to Cloudinary, records the episode in pod/feed/episodes.json, and uploads
# the rebuilt feed.xml to its permanent address, which is the URL Spotify watches.
module Podcast
  class Publisher
    MANIFEST = File.join(Show::FEED_DIR, "episodes.json")
    PREVIEW_FEED = File.join(Show::FEED_DIR, "feed.preview.xml")
    FEED_PUBLIC_ID = "#{Show::CLOUD_FOLDER}/feed.xml".freeze

    def initialize(live: false)
      @live = live
      FileUtils.mkdir_p(Show::FEED_DIR)
    end

    def publish(key:, title:, description:, season:, episode:, audio_path:, art_path:, published_at: Time.current)
      entry = {
        "key" => key, "title" => title, "description" => description, "season" => season, "episode" => episode,
        "published_at" => published_at.iso8601, "duration" => duration(audio_path), "audio_bytes" => File.size(audio_path)
      }
      entry["audio_url"] = upload(audio_path, :video, "#{Show::CLOUD_FOLDER}/episodes/#{key}")
      entry["art_url"] = upload(art_path, :image, "#{Show::CLOUD_FOLDER}/art/#{key}")
      commit(manifest.reject { |existing| existing["key"] == key } + [ entry ])
    end

    # Moves the episodes of the existing Spotify-hosted show (read by Podcast::SpotifyImporter into
    # pod/feed/backup/imported.json) into the new feed, with their original guids. exclude is a list of
    # [season, episode] pairs to leave out, e.g. episodes the new feed replaces.
    def backfill(imported_path: File.join(Show::FEED_DIR, "backup", "imported.json"), exclude: [])
      imported = JSON.parse(File.read(imported_path)).reject { |episode| exclude.include?([ episode["season"], episode["episode"] ]) }
      entries = imported.each_with_index.map do |episode, index|
        $stderr.puts "[backfill] #{index + 1}/#{imported.size} #{episode['title']}" if @live
        stem = File.basename(episode["audio_file"], ".mp3")
        episode.slice("key", "title", "description", "season", "episode", "published_at", "duration", "audio_bytes").merge(
          "audio_url" => upload(episode["audio_file"], :video, "#{Show::CLOUD_FOLDER}/episodes/#{stem}"),
          "art_url" => episode["art_file"] && upload(episode["art_file"], :image, "#{Show::CLOUD_FOLDER}/art/#{stem}")
        )
      end
      keys = entries.pluck("key")
      commit(entries + manifest.reject { |existing| keys.include?(existing["key"]) })
    end

    # Rebuilds and re-uploads the feed from the saved episode list (after changing show metadata or the feed address).
    def rebuild
      commit(manifest)
    end

    private

    # Rebuilds the feed from the full episode list. Live: saves the list and uploads feed.xml. Dry run: writes a
    # preview with placeholder URLs and returns its path.
    def commit(episodes)
      cover_url = upload(cover_file, :image, "#{Show::CLOUD_FOLDER}/cover")
      xml = FeedBuilder.new(feed_url: Show::FEED_URL, cover_url: cover_url, episodes: episodes).call

      if @live
        File.write(MANIFEST, JSON.pretty_generate(episodes))
        file = File.join(Show::FEED_DIR, "feed.xml")
        File.write(file, xml)
        upload(file, :raw, FEED_PUBLIC_ID, uniform_url: true)
        Show::FEED_URL
      else
        File.write(PREVIEW_FEED, xml)
        PREVIEW_FEED
      end
    end

    def manifest
      File.exist?(MANIFEST) ? JSON.parse(File.read(MANIFEST)) : []
    end

    # Cloudinary wants square art of at least 1400px; the show logo file is 1254px, so a scaled copy is used.
    def cover_file
      scaled = File.join(Show::FEED_DIR, "cover_1500.png")
      unless File.exist?(scaled)
        _out, err, status = Open3.capture3("ffmpeg", "-loglevel", "error", "-y", "-i", Show::COVER_SOURCE,
                                           "-vf", "scale=1500:1500:flags=lanczos", scaled)
        raise "ffmpeg failed: #{err}" unless status.success?
      end
      scaled
    end

    def duration(path)
      out, = Open3.capture2("ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path)
      out.to_f.round
    end

    def upload(path, resource_type, public_id, uniform_url: false)
      return "https://example.invalid/#{resource_type}/#{public_id}#{File.extname(path)}" unless @live

      result = Cloudinary::Uploader.upload(path, resource_type: resource_type, public_id: public_id,
                                                 overwrite: true, invalidate: true)
      uniform_url ? cloudinary_url(resource_type, public_id) : result.fetch("secure_url")
    end

    # The unversioned address, which stays the same when the file is overwritten (verified to refresh in ~10s).
    def cloudinary_url(resource_type, public_id)
      "https://res.cloudinary.com/#{Cloudinary.config.cloud_name}/#{resource_type}/upload/#{public_id}"
    end
  end
end
