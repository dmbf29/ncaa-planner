# Episode title and show-page description for a finished script. The title follows one pattern (change it here);
# the description is written by Claude from the script itself, so it only mentions what the episode says.
module Podcast
  class EpisodeInfo
    SYSTEM_PROMPT = <<~PROMPT.freeze
      You write the show-page description for an episode of "#{Show::TITLE}", a two-host Sun Belt football podcast.
      You are given the full script of the episode. Write 2 short paragraphs of plain text, about 150 words in total, (no markdown, no
      bullets, no emoji, no hashtags): the main stories from the recap half, then a teaser of the games previewed and
      the hosts' lean on them. Name teams, scores and storylines that are actually in the script.
      #{PodcastShow::RULES.map { |rule| "- #{rule}" }.join("\n")}
      End with one line: "Hosted by Arlis Boardingham and Ty Simpson." Output only the description.
    PROMPT

    def initialize(script_path:, year:, week_number:, preview_week: nil, model: nil)
      @year = year
      @script_path = script_path
      @script = File.read(script_path)
      @week_number = week_number
      @preview_week = preview_week
      @model = model
    end

    # e.g. "2027 Week 11 Reactions | Week 12 Preview"
    def title
      parts = [ "#{@year} Week #{@week_number} Reactions" ]
      parts << "Week #{@preview_week} Preview" if @preview_week
      parts.join(" | ")
    end

    # Cached next to the script (<script>.description.txt) so previewing the description and publishing the episode
    # use the same text. Delete that file to have it rewritten.
    def description
      @description ||= if File.exist?(cache_path)
        File.read(cache_path).strip
      else
        chat = @model ? RubyLLM.chat(model: @model) : RubyLLM.chat
        text = chat.with_instructions(SYSTEM_PROMPT).ask("<script>\n#{@script}\n</script>").content.strip
        File.write(cache_path, text)
        text
      end
    end

    private

    def cache_path
      @script_path.sub(/\.txt\z/, ".description.txt")
    end
  end
end
