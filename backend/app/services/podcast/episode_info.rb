# Episode title and show-page description for a finished script. The title comes from the EpisodeSpec (change the
# patterns there); the description is written by Claude from the script itself, so it only mentions what the episode says.
module Podcast
  class EpisodeInfo
    COMMON = <<~PROMPT.freeze
      You write the show-page description for an episode of "#{Show::TITLE}", a two-host Sun Belt football podcast.
      You are given the full script of the episode. Write 2 short paragraphs of plain text (no markdown, no bullets,
      no emoji, no hashtags), about 150 words in total. Name teams, scores and storylines that are actually in the script.
      #{PodcastShow::RULES.map { |rule| "- #{rule}" }.join("\n")}
      End with one line: "Hosted by Arlis Boardingham and Ty Simpson." Output only the description.
    PROMPT

    WEEKLY = "First the main stories from the recap half, then a teaser of the games previewed and the hosts' lean on them.".freeze
    RECAP_ONLY = "The main stories from the week's results and what they mean for the standings.".freeze
    SEASON_LONG = "This episode is titled \"%<title>s\". Cover the headline takeaways team by team, and where the hosts land at the end.".freeze

    attr_reader :spec

    def initialize(script_path:, spec:, recap_only: false, model: nil)
      @script_path = script_path
      @script = File.read(script_path)
      @spec = spec
      @recap_only = recap_only
      @model = model
    end

    def title = spec.title(recap_only: @recap_only)

    # Cached next to the script (<script>.description.txt) so previewing the description and publishing the episode
    # use the same text. Delete that file to have it rewritten.
    def description
      @description ||= if File.exist?(cache_path)
        File.read(cache_path).strip
      else
        chat = @model ? RubyLLM.chat(model: @model) : RubyLLM.chat
        text = chat.with_instructions("#{COMMON}\n#{brief}").ask("<script>\n#{@script}\n</script>").content.strip
        File.write(cache_path, text)
        text
      end
    end

    private

    def brief
      return format(SEASON_LONG, title: title) unless spec.weekly?

      @recap_only ? RECAP_ONLY : WEEKLY
    end

    def cache_path
      @script_path.sub(/\.txt\z/, ".description.txt")
    end
  end
end
