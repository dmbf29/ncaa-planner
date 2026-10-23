require "net/http"
require "json"
require "open3"

# Voice bake-off: voices the first N words of a Podcast::ScriptWriter script with ElevenLabs (Text to Dialogue) and
# Gemini (multi-speaker TTS) so the two can be compared blind. Writes mp3s to pod/voice_tests/.
module Podcast
  class VoiceTest
    ELEVENLABS_VOICES = { "ARLIS" => "nPczCjzI2devNBz1zQrb", "TY" => "iP95p4xoKVk53GoZ742B" }.freeze # Brian, Chris
    ELEVENLABS_MAX_CHARS = 2000 # per Text to Dialogue request

    def initialize(script_path:, words: 450, out_dir:)
      @turns = excerpt(File.readlines(script_path, chomp: true), words)
      @out_dir = out_dir
      FileUtils.mkdir_p(out_dir)
    end

    attr_reader :turns

    def elevenlabs
      parts = chunk(turns, ELEVENLABS_MAX_CHARS).each_with_index.map do |group, index|
        body = { model_id: "eleven_v3",
                 inputs: group.map { |turn| { text: turn[:text], voice_id: ELEVENLABS_VOICES.fetch(turn[:speaker]) } } }
        response = post("https://api.elevenlabs.io/v1/text-to-dialogue?output_format=mp3_44100_128", body,
                        "xi-api-key" => ENV.fetch("ELEVENLABS"))
        path = File.join(out_dir, "elevenlabs_part#{index}.mp3")
        File.binwrite(path, response.body)
        path
      end
      join_mp3(parts, File.join(out_dir, "elevenlabs.mp3"))
    end

    def gemini
      wav = File.join(out_dir, "gemini.wav")
      File.binwrite(wav, GeminiSpeech.call(turns))
      ffmpeg("-y", "-i", wav, "-codec:a", "libmp3lame", "-b:a", "128k", File.join(out_dir, "gemini.mp3"))
      File.join(out_dir, "gemini.mp3")
    end

    private

    attr_reader :out_dir

    def excerpt(lines, words)
      count = 0
      lines.filter_map do |line|
        next if count >= words

        match = /\A(ARLIS|TY):\s*(.+)\z/.match(line)
        next unless match

        count += match[2].split.size
        { speaker: match[1], text: match[2] }
      end
    end

    def chunk(turns, max_chars)
      turns.each_with_object([ [] ]) do |turn, groups|
        groups << [] if groups.last.sum { |t| t[:text].size } + turn[:text].size > max_chars
        groups.last << turn
      end
    end

    def post(url, body, headers)
      uri = URI(url)
      request = Net::HTTP::Post.new(uri, { "Content-Type" => "application/json" }.merge(headers))
      request.body = JSON.generate(body)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 300) { |http| http.request(request) }
      raise "#{uri.host} #{response.code}: #{response.body.to_s[0, 600]}" unless response.is_a?(Net::HTTPSuccess)

      response
    end

    def join_mp3(parts, output)
      list = File.join(out_dir, "concat.txt")
      File.write(list, parts.map { |part| "file '#{part}'" }.join("\n"))
      ffmpeg("-y", "-f", "concat", "-safe", "0", "-i", list, "-codec:a", "libmp3lame", "-b:a", "128k", output)
      output
    end

    def ffmpeg(*args)
      _out, err, status = Open3.capture3("ffmpeg", "-loglevel", "error", *args)
      raise "ffmpeg failed: #{err}" unless status.success?
    end
  end
end
