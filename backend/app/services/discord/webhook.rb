require "net/http"

module Discord
  # Posts to, and edits messages in, the channel behind DISCORD_WEBHOOK_URL. Messages are sent with links not unfurled.
  class Webhook
    Error = Class.new(StandardError)
    NotFound = Class.new(Error)

    SUPPRESS_EMBEDS = 1 << 2

    def self.configured?
      ENV["DISCORD_WEBHOOK_URL"].present?
    end

    def initialize(url = ENV["DISCORD_WEBHOOK_URL"])
      @url = url
    end

    # Returns the id of the new message.
    def post(content)
      raise Error, "DISCORD_WEBHOOK_URL is not set." if @url.blank?

      uri = URI(@url)
      uri.query = "wait=true"
      JSON.parse(send_request(Net::HTTP::Post, uri, content).body).fetch("id")
    end

    def edit(message_id, content)
      raise Error, "DISCORD_WEBHOOK_URL is not set." if @url.blank?

      send_request(Net::HTTP::Patch, URI("#{@url}/messages/#{message_id}"), content)
    end

    private

    def send_request(verb, uri, content)
      request = verb.new(uri, "Content-Type" => "application/json")
      request.body = { content: content, flags: SUPPRESS_EMBEDS, allowed_mentions: { parse: [] } }.to_json
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
      raise NotFound, "Discord message not found" if response.code == "404"
      raise Error, "Discord returned #{response.code}: #{response.body.to_s.truncate(200)}" unless response.is_a?(Net::HTTPSuccess)

      response
    end
  end
end
