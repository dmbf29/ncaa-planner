# Checks a Podcast::ScriptWriter script against the Markdown sources it was written from and rewrites any turn that
# says something the sources don't support (a wrong score, record or ranking, a home/away mix-up, a stat credited to
# the wrong player, an invented storyline). NotebookLM is grounded in its sources by construction; a model writing
# free-form dialogue isn't, so this is the second pair of eyes before anything is voiced.
#
# The script is checked in numbered chunks of turns, each against the full sources. The checker answers in plain
# ISSUE blocks (not structured output, for the same variable-length-array reason as the script itself) and must
# quote the source line that contradicts the turn; an issue without that evidence is dropped, so the checker can't
# "correct" a true statement on a hunch.
module Podcast
  class FactChecker
    CHUNK_TURNS = 25

    # Hard mismatches against a number, team, player or line in the sources are rewritten automatically. Anything
    # else the checker thinks is wrong ("invented", "other") is a judgment call, so it is only reported with a
    # proposed fix for a human to accept or ignore.
    AUTO_FIX_TYPES = %w[wrong_number wrong_team home_away wrong_player wrong_line].freeze

    Issue = Struct.new(:turn, :type, :claim, :evidence, :fix, :rejection, keyword_init: true)

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the fact-checker for a two-host sports audio show. You are given the source documents the script was
      written from and a numbered run of dialogue turns. Find every turn that states something the sources contradict
      or do not support, and write a corrected version of that turn.

      SCOPE
      - The episode is ONE show named "#{ScriptWriter::SHOW_NAME}" that combines a recap and a preview. The sources
        were written for separate shows, so IGNORE everything in them about show names, hosts' openings and sign-offs,
        "Next Episode" teases, broadcast dates, run-of-show and any "DO NOT READ ALOUD" producer notes. Those are
        directions, not facts, and the script intentionally departs from them. Never "fix" the show name, an
        introduction, a sign-off, or a weekday/date omission.

      CHECK
      - Scores, records, rankings (CFP rank vs. poll rank are different things), streaks, standings, stats and who did what.
      - Home vs. away: "A @ B" means A is the road team and B is the home team. "vs" means the first team is at home.
      - Which team a player belongs to, positions, and who a coach is.
      - Betting lines, totals and each host's bet in the preview: they must match the source's lines and Call lines.
      - Anything specific (a play, a quote, a trend, a head-to-head result, a "first time since") that the sources do
        not state. Invented specifics are errors even if they sound plausible.
      - Spoken numbers: the dialogue spells numbers out ("two hundred thirty-four"); convert them before comparing.

      DO NOT FLAG
      - Real-world public knowledge about the real schools and the sport: where a university is located (Marshall
        is in Huntington, Coastal Carolina in Conway), mascots, stadium cities, how football works. The show treats
        this as real college football, so ordinary real-world knowledge is expected and is NOT an invented fact.
      - Spoken betting phrasing. "A field goal and a half" is three and a half points (a field goal plus a half
        point). Only flag a line if the number it means differs from the source's number.
      - A matchup claim the sources simply don't rate (for example a hosts' take on a team's offensive line when the
        source only lists other matchups) unless the sources contradict it. Football reasoning is not an error.
      - Opinion, analysis, rhetorical flourish, banter, predictions, or reasonable inferences that follow from the
        numbers (e.g. "that's a big margin", "momentum swung").
      - Rounding a number naturally ("nearly forty-seven points a game" for 46.9).
      - Anything you are unsure about. Only flag what the sources clearly contradict or clearly do not contain.
      - Style. Do not flag how something is phrased.

      FIXING
      - FIX is the COMPLETE replacement text for the turn (not a diff), in the same speaker's voice, spoken style,
        number-words and length. Change as little as possible: correct the fact, or remove the unsupported specific
        and keep the rest of the line. If the whole turn is unsupported, write a short natural line in its place.
      - A fix must never add a new specific of its own (a play, a sequence, a stat, a reason) that the sources don't
        state. Use only wording and numbers the sources support, or generalize ("held scoreless in the fourth").
      - Each issue MUST include a SOURCE line quoting the source text that contradicts the turn, or, for an invented
        specific, quoting the closest source text showing it is absent. Without one, do not report it.

      LEAGUE HISTORY
      - A source named history.md, when present, is the league's record of earlier seasons and counts as a source. Claims
        about earlier seasons, "first time" / "second time" / "reigning champion" / series records must match its
        tallies; a "first" the history contradicts is a wrong_number, and a historic claim it doesn't contain is invented.

      SOURCE QUIRKS
      - In a team's "THIS WEEK AT A GLANCE" row, "Record Entering" is the record BEFORE that week's game, while the
        "Ranking" column (e.g. "#10 (up from #11)", "Just cracked the Top 25 at #24") is the poll ranking AFTER the
        week. The CFP rankings table is a separate ranking with its own trend arrows. Do not mix the two.

      OUTPUT FORMAT. Give a verdict for EVERY turn, in order: for a turn with nothing wrong, the single line
      `<turn number>: OK`. For a turn with a problem, one block (and no OK line for it):

      ISSUE
      TURN: <turn number>
      TYPE: <wrong_number | wrong_team | home_away | wrong_player | wrong_line | invented | other>
      CLAIM: <what the turn says that is wrong, one short sentence>
      SOURCE: <quoted source text>
      FIX: <complete replacement turn text, without the speaker label>
      END

      Check every turn's claims one at a time before giving its verdict; do not skim.
    PROMPT

    CONFIRM_PROMPT = <<~PROMPT.freeze
      You are the second reviewer on a sports-show fact-check. A first reviewer flagged one line of dialogue as
      contradicting the source documents. Decide whether the flag is correct. Be skeptical: reject it if the line is
      supported by the sources under a reasonable reading, if the reviewer misread the source, or if the proposed fix
      itself adds ANY detail (a play, a sequence, a reason, a number) the sources don't state. Also reject any flag
      about a show name, an introduction or sign-off, a "Next Episode" tease, or a date or weekday: the episode is one
      show named "#{ScriptWriter::SHOW_NAME}" and the sources' show directives intentionally don't apply. Note that in a "THIS WEEK AT A GLANCE" row, "Record Entering"
      is the record before the game and "Ranking" is the poll ranking after the week; the CFP table is separate.

      Answer with exactly one line: `CONFIRMED` or `REJECTED: <reason>`.
    PROMPT

    def initialize(turns:, source_paths:, model: nil)
      @turns = turns
      @sources = source_paths.map { |path| [ File.basename(path), File.read(path) ] }
      @model = model
    end

    # Returns [issues, corrected_turns].
    def call
      issues = []
      numbered_chunks.each_with_index do |chunk, index|
        $stderr.puts "[factcheck] chunk #{index + 1}/#{numbered_chunks.size}"
        issues.concat(check(chunk))
      end
      issues = issues.uniq(&:turn)
      confirmed, @rejected = issues.partition { |issue| confirmed?(issue) }
      fixed, @needs_review = confirmed.partition { |issue| AUTO_FIX_TYPES.include?(issue.type) }
      [ fixed, apply(fixed) ]
    end

    def self.report(fixed, turns, needs_review = [], rejected = [])
      sections = []
      sections << "# Fixed automatically\n\n#{fixed.map { |issue| entry(issue, turns, "Fixed") }.join("\n")}" if fixed.any?
      if needs_review.any?
        sections << "# Needs your call (NOT changed)\n\n#{needs_review.map { |issue| entry(issue, turns, "Suggested fix") }.join("\n")}"
      end
      if rejected.any?
        skipped = rejected.map { |issue| "- Turn #{issue.turn}: #{issue.claim} (not changed: #{issue.rejection})" }
        sections << "# Flagged but NOT changed (second reviewer disagreed)\n\n#{skipped.join("\n")}"
      end
      sections.empty? ? "No issues found.\n" : "#{sections.join("\n\n")}\n"
    end

    def self.entry(issue, turns, fix_label)
      original = turns[issue.turn - 1]
      <<~ENTRY
        ## Turn #{issue.turn} (#{original[:speaker]}) — #{issue.type}
        **Said:** #{original[:text]}
        **Problem:** #{issue.claim}
        **Source:** #{issue.evidence}
        **#{fix_label}:** #{issue.fix}
      ENTRY
    end

    # Flags the second reviewer threw out, kept so the report can show them for a human look.
    attr_reader :rejected

    # Confirmed issues of a judgment-call type, reported but not applied.
    attr_reader :needs_review

    private

    attr_reader :turns, :sources, :model

    def numbered_chunks
      @numbered_chunks ||= turns.each_with_index.map { |turn, index| [ index + 1, turn ] }.each_slice(CHUNK_TURNS).to_a
    end

    def chat
      chat = model ? RubyLLM.chat(model: model) : RubyLLM.chat
      chat.with_instructions(SYSTEM_PROMPT)
    end

    def check(chunk)
      parse(chat.ask(prompt(chunk)).content, chunk.map(&:first))
    end

    # Second opinion on a single flagged turn, so a misreading by the first pass doesn't rewrite a true statement.
    def confirmed?(issue)
      $stderr.puts "[factcheck] confirming turn #{issue.turn}"
      reply = confirm_chat.ask(<<~PROMPT).content
        #{sources_block}

        Flagged line: #{turns[issue.turn - 1][:text]}
        Reviewer's claim: #{issue.claim}
        Reviewer's source quote: #{issue.evidence}
        Reviewer's proposed fix: #{issue.fix}
      PROMPT
      issue.rejection = reply.strip.delete_prefix("REJECTED:").strip
      reply.strip.start_with?("CONFIRMED")
    end

    def confirm_chat
      chat = model ? RubyLLM.chat(model: model) : RubyLLM.chat
      chat.with_instructions(CONFIRM_PROMPT)
    end

    def sources_block
      sources.map { |name, text| "<source name=\"#{name}\">\n#{text}\n</source>" }.join("\n\n")
    end

    def prompt(chunk)
      lines = chunk.map { |number, turn| "[#{number}] #{turn[:speaker]}: #{turn[:text]}" }.join("\n")
      <<~PROMPT
        #{sources_block}

        Check these turns of the script (turn numbers are in brackets):

        #{lines}
      PROMPT
    end

    def parse(raw, valid_turns)
      raw.scan(/^ISSUE\s*\n(.*?)^END\s*$/m).filter_map do |(block)|
        fields = block.scan(/^(TURN|TYPE|CLAIM|SOURCE|FIX):[ \t]*(.*?)(?=^(?:TURN|TYPE|CLAIM|SOURCE|FIX):|\z)/m).to_h { |key, value| [ key, value.strip ] }
        turn = fields["TURN"].to_i
        next unless valid_turns.include?(turn) && fields["FIX"].present? && fields["SOURCE"].present?

        Issue.new(turn: turn, type: fields["TYPE"], claim: fields["CLAIM"], evidence: fields["SOURCE"],
                  fix: fields["FIX"].sub(/\A(ARLIS|TY):\s*/, "").tr("\n", " "))
      end
    end

    def apply(issues)
      fixes = issues.to_h { |issue| [ issue.turn, issue.fix ] }
      turns.each_with_index.map do |turn, index|
        fixes.key?(index + 1) ? turn.merge(text: fixes[index + 1]) : turn
      end
    end
  end
end
