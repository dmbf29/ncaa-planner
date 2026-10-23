require "nokogiri"
require "json"
require "open3"
require "uri"

# Reads the show's existing Spotify-hosted RSS feed and copies everything out of it: the audio and artwork for every
# episode into pod/feed/backup/, plus imported.json (the metadata, original guids included) that the new feed is built
# from. Downloads are resumable (a file that already has the right size is skipped) and nothing here talks to Cloudinary
# or changes the live show.
module Podcast
  class SpotifyImporter
    BACKUP_DIR = File.join(Show::FEED_DIR, "backup")
    FEED_COPY = File.join(BACKUP_DIR, "spotify_feed.xml")
    ITUNES = { "itunes" => "http://www.itunes.com/dtds/podcast-1.0.dtd" }.freeze

    def initialize(feed_path: FEED_COPY)
      @doc = Nokogiri::XML(File.read(feed_path))
      FileUtils.mkdir_p([ File.join(BACKUP_DIR, "audio"), File.join(BACKUP_DIR, "art") ])
    end

    # Downloads every episode's audio and art and writes imported.json. Returns the episode hashes (oldest first).
    def call
      episodes = items.each_with_index.map { |item, index| download(episode_for(item), index + 1, items.size) }
      File.write(File.join(BACKUP_DIR, "imported.json"), JSON.pretty_generate(episodes))
      episodes
    end

    def items
      @items ||= @doc.xpath("//channel/item").reverse
    end

    private

    def episode_for(item)
      enclosure = item.at_xpath("enclosure")
      {
        "key" => item.at_xpath("guid").text, # the ORIGINAL guid, so Spotify/Apple see the same episodes
        "title" => item.at_xpath("title").text.strip,
        "description" => Nokogiri::HTML.fragment(item.at_xpath("description").text).text.strip,
        "season" => item.at_xpath("itunes:season", ITUNES)&.text.to_i,
        "episode" => item.at_xpath("itunes:episode", ITUNES)&.text.to_i,
        "published_at" => Time.rfc2822(item.at_xpath("pubDate").text).iso8601,
        "duration" => duration_seconds(item.at_xpath("itunes:duration", ITUNES)&.text),
        "audio_bytes" => enclosure["length"].to_i,
        "source_audio_url" => enclosure["url"],
        "source_art_url" => item.at_xpath("itunes:image", ITUNES)&.[]("href")
      }
    end

    def download(episode, number, total)
      stem = "#{episode['published_at'][0, 10]}_#{episode['key'][0, 8]}"
      audio = File.join(BACKUP_DIR, "audio", "#{stem}.mp3")
      fetch(episode["source_audio_url"], audio, episode["audio_bytes"], "#{number}/#{total} #{episode['title']}")
      art = File.join(BACKUP_DIR, "art", "#{stem}#{File.extname(URI(episode['source_art_url']).path).presence || '.jpg'}") if episode["source_art_url"]
      fetch(episode["source_art_url"], art, nil, nil) if art
      episode.merge("audio_file" => audio, "art_file" => art)
    end

    def fetch(url, path, expected_bytes, label)
      return if File.exist?(path) && (expected_bytes.nil? || File.size(path) == expected_bytes) && File.size(path).positive?

      $stderr.puts "[import] #{label}" if label
      _out, err, status = Open3.capture3("curl", "-sSL", "--fail", "--retry", "3", "-o", path, url)
      raise "download failed for #{url}: #{err}" unless status.success?
      return unless expected_bytes && File.size(path) != expected_bytes

      raise "#{path}: got #{File.size(path)} bytes, feed says #{expected_bytes}"
    end

    def duration_seconds(text)
      text.to_s.split(":").map(&:to_i).inject(0) { |sum, part| sum * 60 + part }
    end
  end
end
