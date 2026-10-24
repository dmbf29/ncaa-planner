require "net/http"
require "json"
require "base64"

# Episode cover art via the OpenAI image API, in the style of the existing weekly art: the show logo and the
# previous episode's art go in as references, and Claude first boils the preview source down to the exact text each
# game panel should show (teams, line, total, both hosts' picks) so the image model isn't left to read a long document.
module Podcast
  class ArtworkGenerator
    MODEL = "gpt-image-2.5-sunburst".freeze # the "editing precision" model; see developers.openai.com image docs
    SIZE = "1536x1536".freeze # Spotify/Apple want square art of at least 1400px

    FACTS_PROMPT = <<~PROMPT.freeze
      From the preview source below, write the exact on-image text for each game panel, one panel per game in the
      document's order, in this format and nothing else. A game is a section headed "## 🏈 GAME n OF m" and no
      other. NEVER make a panel for the games listed under "ALSO ON THE BOARD": they are heads-ups with no bets, so
      they have no picks and must not appear on the cover.

      PANEL 1: <Away team> @ <Home team> (include a ranking like "No. 7" only if the source gives one)
      KICKOFF: <short day, date, time and network, e.g. "SAT, NOV 20 • 8:00 PM ET • ESPN">
      SPREAD: <favorite short name and line, e.g. "UL MONROE -25.5">
      TOTAL: <total, e.g. "58.5">
      ARLIS PICK: <short pick, e.g. "UL MONROE -25.5" or "UNDER 44.5">
      TY PICK: <short pick>

      Convert the spoken picks ("minus twenty-five and a half") into numerals. Use only what the source states.
    PROMPT

    def initialize(preview_path:, recap_week:, preview_week:, out_path:, preview_label: nil, recap_label: nil, model: nil)
      @preview = File.read(preview_path)
      @recap_week = recap_week
      @preview_week = preview_week
      @recap_label = recap_label.presence || "Week #{recap_week}"
      @preview_label = preview_label.presence || "Week #{preview_week}"
      @out_path = out_path
      @model = model
    end

    def call
      facts = (@model ? RubyLLM.chat(model: @model) : RubyLLM.chat).with_instructions(facts_prompt).ask(facts_request).content
      prompt = image_prompt(facts)
      File.write(out_path.sub(/\.png\z/, "_prompt.txt"), prompt)
      File.binwrite(out_path, Base64.decode64(request_image(prompt)))
      out_path
    end

    private

    attr_reader :out_path

    def facts_prompt = FACTS_PROMPT

    # The source is a show script brief; wrap it so it is read as data to extract from, not as a job to perform.
    def facts_request
      "<source>\n#{@preview}\n</source>\n\nExtract the panel text now. Output only the PANEL blocks."
    end

    def references
      previous = Dir[File.join(Show::ART_DIR, "*_bgb.png")].max
      [ Show::COVER_SOURCE, previous ].compact.select { |path| File.exist?(path) && path != out_path }
    end

    def image_prompt(facts)
      <<~PROMPT
        Create a square podcast episode cover in the same style as the reference images. Image 1 is the show logo
        ("Rising in the Sun Belt", a sunburst over palm trees); reproduce that logo in the top-left corner. Image 2 is
        last week's episode cover: copy its layout, its stadium-at-sunset background, its bold brush-lettering
        headline, its four colored game panels, the football-helmet matchups in each team's real colors, and the two
        host headshots (Arlis Boardingham and Ty Simpson) in "THE PICKS" strip of every panel.

        Headline (large brush lettering, same placement as before): "#{@recap_label.upcase} REACTIONS + #{@preview_label.upcase} PREVIEW".
        Small tag next to it: "RECAP. PREVIEW. ALL SUN BELT."

        Each panel's text must read exactly as follows, with each panel's spread and total shown in boxes and the two
        picks under "THE PICKS" beside the hosts' photos. Spell every word and number exactly as written:

        #{facts}
      PROMPT
    end

    def request_image(prompt)
      boundary = "----claude#{SecureRandom.hex(8)}"
      body = "".b
      { "model" => MODEL, "prompt" => prompt, "size" => SIZE, "quality" => "high", "output_format" => "png" }.each do |key, value|
        body << "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{key}\"\r\n\r\n#{value}\r\n".b
      end
      references.each do |path|
        body << "--#{boundary}\r\nContent-Disposition: form-data; name=\"image[]\"; filename=\"#{File.basename(path).gsub(/[^A-Za-z0-9._-]/, "_")}\"\r\n" \
                "Content-Type: image/png\r\n\r\n".b << File.binread(path) << "\r\n".b
      end
      body << "--#{boundary}--\r\n".b

      uri = URI("https://api.openai.com/v1/images/edits")
      request = Net::HTTP::Post.new(uri, "Authorization" => "Bearer #{ENV.fetch('OPENAI_API_KEY')}",
                                         "Content-Type" => "multipart/form-data; boundary=#{boundary}")
      request.body = body
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 600) { |http| http.request(request) }
      raise "OpenAI #{response.code}: #{response.body.to_s[0, 600]}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body).dig("data", 0, "b64_json") or raise "No image in OpenAI response"
    end
  end
end
