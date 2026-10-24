# The season-long shows (win totals, roster breakdown, report cards, portal preview, signing day) as a two-host script.
# Each exported markdown already carries its own format spec: producer notes ("DO NOT READ ALOUD"), a mandatory opening
# and a run-of-show list. This writer follows them generically: one script segment per run-of-show item, the producer
# notes and the show-specific rules (EpisodeSpec) in the system prompt, the whole document as the only source of facts.
# Output, running summary and parsing are inherited from ScriptWriter.
module Podcast
  class ShowScriptWriter < ScriptWriter
    WORDS_PER_MINUTE = 185
    OPENING_WORDS = 220
    # Round-up style segments are shorter than a per-team segment.
    LIGHT_SEGMENT = /around the|champion|wrap|ranking|improve|hardware|hit hardest|predicted/i

    def initialize(markdown_path:, spec:, model: nil)
      @markdown = File.read(markdown_path)
      @spec = spec
      @model = model
    end

    private

    attr_reader :spec

    def segments
      @segments ||= begin
        titles = run_of_show
        raise "No run-of-show found in the #{spec.kind} source document" if titles.empty?

        weights = titles.map { |title| title.match?(LIGHT_SEGMENT) ? 0.7 : 1.0 }
        budget = [ spec.minutes * WORDS_PER_MINUTE - OPENING_WORDS, 400 ].max
        [ opening ] + titles.each_with_index.map do |title, index|
          show_segment(title, index, titles.size, (budget * weights[index] / weights.sum).round)
        end
      end
    end

    # "- **Segment 3:** Marshall — Schedule Read + ..." lines under the run-of-show heading.
    def run_of_show
      markdown.scan(/^- \*\*Segment \d+:\*\* (.+)$/).flatten
    end

    def opening
      Segment.new(
        label: "Opening", kind: :show, words: OPENING_WORDS,
        instruction: <<~TEXT
          Write the cold open of "#{SHOW_NAME}" for this show ("#{spec.title}"). Follow the document's MANDATORY SHOW OPENING
          exactly (its text is in the producer notes above): the opening line, then both hosts' introductions word for
          word. Then, in a few lines, set up what's ahead. Do NOT start on the first segment's content.
        TEXT
      )
    end

    def show_segment(title, index, total, words)
      last = index == total - 1
      Segment.new(
        label: title, kind: :show, words: words,
        instruction: <<~TEXT
          Write run-of-show segment #{index + 1} of #{total}: "#{title}", using the matching section of the document and
          following the producer notes' format for it in full. Cover this segment only; the others get their own turn.
          #{index.zero? ? 'Continue straight on from the opening; do not re-introduce the show or the hosts.' : 'Continue from the previous segment with a natural handoff; do not re-introduce the show.'}
          #{last ? "This is the final segment: end it with a short, warm sign-off from both hosts (\"see you next time\"), naming the show. Do NOT tease or name any specific upcoming episode." : 'End with a natural handoff, not a goodbye.'}
        TEXT
      )
    end

    def chat(_segment)
      chat = model ? RubyLLM.chat(model: model) : RubyLLM.chat
      chat.with_instructions([ SYSTEM_PROMPT, show_rules, producer_notes ].reject(&:blank?).join("\n\n"))
    end

    def show_rules
      return nil if spec.rules.blank?

      "SHOW-SPECIFIC RULES for this episode:\n#{spec.rules}"
    end

    # Every "## ... PRODUCER NOTE ..." section plus the mandatory opening, verbatim from the document.
    def producer_notes
      sections = markdown.split(/^(?=## )/).select { |section| section.start_with?("## ") && section.lines.first.match?(/PRODUCER NOTE|MANDATORY SHOW OPENING/) }
      "THE PRODUCER'S FORMAT NOTES FOR THIS SHOW (these govern it; they are directions, not text to read aloud):\n\n#{sections.join("\n")}"
    end

    def segment_prompt(segment, summary)
      <<~PROMPT
        Here is the source document for this episode. It is the only source of facts.

        <source>
        #{markdown}
        </source>

        #{summary.empty? ? "Nothing has been said yet; this is the first segment." : "Already covered in the show so far (do not repeat these points or re-introduce the hosts):\n- #{summary.join("\n- ")}"}

        SEGMENT TO WRITE NOW: #{segment.label}
        #{segment.instruction}
        Length: about #{segment.words} words of dialogue. Output only the dialogue lines.
      PROMPT
    end
  end
end
