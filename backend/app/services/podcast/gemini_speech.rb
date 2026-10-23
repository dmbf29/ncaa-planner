require "net/http"
require "json"
require "base64"

# Gemini multi-speaker TTS: voices a run of { speaker:, text: } turns in one conversational request and returns WAV
# bytes (24 kHz, mono, 16-bit). Voices picked from the Sadachbia/Orus, Algenib/Achird and Charon/Puck auditions.
module Podcast
  class GeminiSpeech
    MODEL = "gemini-3.8-flash-tts".freeze
    URL = "https://generativelanguage.googleapis.com/v1beta/interactions".freeze
    SPEAKERS = {
      "ARLIS" => { name: "Arlis", voice: "Algenib", style: "warm, cinematic and emotional, like a veteran studio host" },
      "TY" => { name: "Ty", voice: "Orus", style: "sharp, upbeat and analytical, with quick energy" }
    }.freeze
    ATTEMPTS = 3

    def self.call(turns)
      new(turns).call
    end

    def initialize(turns)
      @turns = turns
    end

    def call
      attempts = 0
      begin
        attempts += 1
        audio = find_base64_audio(JSON.parse(post(request_body).body))
        raise "No audio in Gemini response" unless audio

        Base64.decode64(audio)
      rescue StandardError => error
        raise if attempts >= ATTEMPTS

        $stderr.puts "[gemini] #{error.message.lines.first&.strip} (retry #{attempts}/#{ATTEMPTS - 1})"
        sleep 3 * attempts
        retry
      end
    end

    private

    attr_reader :turns

    def request_body
      {
        model: MODEL,
        input: [ { type: "user_input", content: turns.map { |turn| content_for(turn) } } ],
        response_format: { type: "audio" },
        generation_config: {
          speech_config: { mode: "conversational",
                           speakers: SPEAKERS.values.map { |speaker| { speaker: speaker[:name], voice: speaker[:voice] } } }
        }
      }
    end

    def content_for(turn)
      speaker = SPEAKERS.fetch(turn[:speaker])
      { type: "text", text: turn[:text],
        annotations: [ { type: "speech_metadata", speaker: speaker[:name], style: speaker[:style] } ] }
    end

    def post(body)
      uri = URI(URL)
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "x-goog-api-key" => ENV.fetch("GEMINI_API_KEY"))
      request.body = JSON.generate(body)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 300) { |http| http.request(request) }
      raise "Gemini #{response.code}: #{response.body.to_s[0, 600]}" unless response.is_a?(Net::HTTPSuccess)

      response
    end

    def find_base64_audio(node)
      case node
      when Hash then node.each_value { |value| (found = find_base64_audio(value)) && (return found) } && nil
      when Array then node.each { |value| (found = find_base64_audio(value)) && (return found) } && nil
      when String then node if node.size > 1000 && node.match?(/\A[A-Za-z0-9+\/=\s]+\z/)
      end
    end
  end
end
