require "nokogiri"

# Builds the podcast RSS 2.0 feed (with the iTunes tags Spotify and Apple read) from the show metadata and a list of
# episode hashes. Pure: no network, no files.
module Podcast
  class FeedBuilder
    ITUNES = "http://www.itunes.com/dtds/podcast-1.0.dtd".freeze
    ATOM = "http://www.w3.org/2005/Atom".freeze

    # episodes: hashes with string keys: key, title, description, season, episode, published_at (ISO 8601),
    # duration (seconds), audio_url, audio_bytes, art_url. Newest first in the feed.
    def initialize(feed_url:, cover_url:, episodes:)
      @feed_url = feed_url
      @cover_url = cover_url
      @episodes = episodes.sort_by { |episode| Time.iso8601(episode["published_at"]) }.reverse
    end

    def call
      Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
        xml.rss(version: "2.0", "xmlns:itunes" => ITUNES, "xmlns:atom" => ATOM) do
          xml.channel do
            channel(xml)
            @episodes.each { |episode| item(xml, episode) }
          end
        end
      end.to_xml
    end

    private

    def channel(xml)
      xml.title Show::TITLE
      xml.link @feed_url
      xml.language Show::LANGUAGE
      xml.description Show::DESCRIPTION
      xml["atom"].link(href: @feed_url, rel: "self", type: "application/rss+xml")
      xml["itunes"].author Show::AUTHOR
      xml["itunes"].summary Show::DESCRIPTION
      xml["itunes"].explicit "false"
      xml["itunes"].type "episodic"
      xml["itunes"].image(href: @cover_url)
      xml["itunes"].category(text: Show::CATEGORY)
      return unless Show::OWNER_EMAIL

      xml["itunes"].owner do
        xml["itunes"].name Show::AUTHOR
        xml["itunes"].email Show::OWNER_EMAIL
      end
    end

    def item(xml, episode)
      xml.item do
        xml.title episode["title"]
        xml.description { xml.cdata episode["description"].to_s.gsub("\n", "<br>") }
        xml.enclosure(url: episode["audio_url"], length: episode["audio_bytes"], type: "audio/mpeg")
        xml.guid(episode["key"], isPermaLink: "false")
        xml.pubDate Time.iso8601(episode["published_at"]).utc.rfc2822
        xml["itunes"].title episode["title"]
        xml["itunes"].duration episode["duration"].to_i
        xml["itunes"].season episode["season"]
        xml["itunes"].episode episode["episode"]
        xml["itunes"].episodeType "full"
        xml["itunes"].explicit "false"
        xml["itunes"].image(href: episode["art_url"]) if episode["art_url"]
      end
    end
  end
end
