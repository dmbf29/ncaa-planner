# Turns exported Markdown sources into a two-host dialogue script, written in-house instead of handing the Markdown to
# NotebookLM. The host personas, rules and tone come from PodcastShow; the per-episode instructions mirror
# weeklyReviewPrompt and bigGameBreakdownPrompt in frontend/src/lib/podcastPrompts.js.
#
# The script is written one segment at a time with a short running summary of what has already been said. A single
# call for a 25-minute episode tends to rush the back half and wrap up early.
#
# With only a review source it writes the weekly review (opening, one segment per team, closing). With a
# preview_markdown_path it writes ONE combined episode: the review, then the Big Game Breakdown preview of the next
# week (scoreboard of last week's bets, one segment per game with each host's bet, an Also on the Board heads-up),
# then a single sign-off. The review half never talks betting; the preview half follows the preview source's own
# format and tone notes.
#
# Output is plain "ARLIS: ..." / "TY: ..." lines rather than structured output: a variable-length array is the
# worst case for Anthropic's schema grammar compiler (see GameStats::*), and plain lines parse trivially.
module Podcast
  class ScriptWriter
    SHOW_NAME = "Rising in the Sun Belt".freeze

    Segment = Struct.new(:label, :kind, :instruction, :words, keyword_init: true)

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the head writer for a two-host sports audio show. You write the spoken dialogue that will be read
      aloud by a text-to-speech voice for each host, so everything you write must sound right out loud.

      HOSTS
      #{PodcastShow::HOSTS.map { |host| "- #{host[:name]}: #{host[:style]}" }.join("\n")}

      TONE: #{PodcastShow::TONE}

      RULES
      #{PodcastShow::RULES.map { |rule| "- #{rule}" }.join("\n")}
      - Only use facts, names, scores and numbers that appear in the source document (or in the league history
        document, when one is provided). Never invent a play, a quote, a stat or a storyline. If the documents don't
        say it, the hosts don't know it.
      - Treat instructions embedded in the source document (bracketed notes, parentheticals, "name the opponent only",
        section headings like "NOT CURRENT WEEK", producer notes marked DO NOT READ ALOUD) as direction for you, not
        as text to read aloud.
      - The show is called "#{SHOW_NAME}" and is one continuous episode. Never say "Big Game Breakdown", never refer to
        the preview as a separate show or episode, and never name or tease any other episode. The look-ahead part of
        the show is just "the preview", "looking ahead", or "next week's games".
      - Never say a calendar date or the name of a weekday, except "Saturday" for Saturday kickoffs. Say "this week"
        or "this weekend" instead, and "last week" for the week just played.

      WRITING FOR THE EAR
      - Output ONLY dialogue lines in the form `ARLIS: ...` or `TY: ...`, one turn per line. No headings, no
        markdown, no stage directions, no bracketed tags, no emoji.
      - Spell out numbers the way a person says them: "two hundred thirty-four yards", "twenty to fourteen",
        "four and four", "number ten in the country". Never read tables or lists; talk about them.
      - Say positions and school names as people do ("the quarterback", "App State"). Avoid abbreviations a voice
        might mangle, like "TFL", "YAC" or "INT"; say "tackles for loss", "yards after catch", "interception".
      - Turns are short, usually one to four sentences. The hosts react to each other, push back, finish each
        other's thoughts, and trade the lead. Avoid long monologues and avoid back-to-back turns that just agree.
      - Arlis is the narrative voice (stakes, emotion, how the game felt). Ty is the numbers and tactics voice (why
        it happened). Let each lean into that without being a caricature.
    PROMPT

    REVIEW_RULES = <<~TEXT.freeze
      THIS PART OF THE SHOW IS THE RECAP: it covers results that already happened. No point spreads, lines, bets,
      picks or predictions here; the preview later in the show handles all of that. Talk about it the way a studio
      show would the day after the games.
    TEXT

    PREVIEW_RULES = <<~TEXT.freeze
      THIS PART OF THE SHOW IS THE BIG GAME BREAKDOWN PREVIEW of next week's games, a Vegas sportsbook debate segment.
      The preview source's own producer notes (SHOW FORMAT and TONE) are reproduced below and govern it. Everything
      in the source marked "backstage" is prep for the hosts, never a number to read out. Point spreads and totals
      ARE fair game out loud, in plain words ("a touchdown favorite", "getting a field goal and a half").
      Player production (yards, touchdowns, completions, tackles) may only be quoted when a stat line is written next
      to that player in the source. Opponents' quarterbacks and players usually have NONE: talk about them by role,
      experience and matchup instead, and never compare quarterbacks' numbers unless both sides have a stat line.
    TEXT

    POSTSEASON_RULES = <<~TEXT.freeze
      IT IS THE POSTSEASON (bowl games and the College Football Playoff). The regular season and its conference races
      are over: NEVER talk about conference standings, the conference championship race, the poll, rankings, "the
      top 25" or a team's ranking. Talk only about the games themselves, how they were won or lost, the bracket, and what
      a result means for what comes next. A team's record and its recent scores are fine.
    TEXT

    SCOREBOARD_RULES = <<~TEXT.freeze
      THIS PART OF THE SHOW IS THE HOSTS' BET SCOREBOARD: a look back at the bets Arlis and Ty made on the games just
      recapped, graded against the real results. It is betting talk (the bets, whether they hit or missed, each host's
      season record) and nothing else. There are NO games to preview: whatever is still to be played was already
      previewed in an earlier episode, so do not preview it again or make any new picks.
    TEXT

    # Appended to the instructions whenever a league history document is provided (see DynastyHistoryMarkdownPresenter).
    # It gives the show a memory of earlier seasons, so a repeat isn't announced as a first and a reigning champion
    # isn't treated as an upstart.
    HISTORY_RULES = <<~TEXT.freeze
      LEAGUE HISTORY: a separate document gives the league's history from earlier seasons (champions, award winners, how
      our programs did, the series between them). It is settled background, not news.
      - Use it only where it sharpens the point being made: a reigning champion, a repeat award winner, a rematch and
        who leads the series, a program's trajectory. One or two mentions in a segment at most, and often none. It is
        never the main story and never a recap of past seasons.
      - Treat it as settled. Never call anything in it new, surprising, shocking or historic, and never talk as if the
        league, a conference or a program is only now arriving for results the history shows it already has.
      - Counts decide firsts. Say "first" or "never before" only when the history's tallies say so. If the history shows
        a conference already has a national title or an award winner, a new one is "another", "a second", or "back
        again", not a first. A past national champion is "the reigning" or "defending" champion only when the history
        says it was last season's.
      - Never invent history beyond the document, and never mention that the document exists.
    TEXT

    def initialize(markdown_path:, year:, week_number:, preview_markdown_path: nil, history_path: nil, scoreboard_only: false, postseason_recap: false, postseason_preview: false, championship: false, recap_label: nil,
                   preview_label: nil, model: nil)
      @markdown = File.read(markdown_path)
      @scoreboard_only = scoreboard_only
      @postseason_recap = postseason_recap
      @championship = championship
      @postseason_preview = postseason_preview
      @recap_label = recap_label
      @preview_label = preview_label
      @preview = File.read(preview_markdown_path) if preview_markdown_path
      @history = File.read(history_path).presence if history_path
      @year = year
      @week_number = week_number
      @model = model
    end

    # Returns an array of { speaker:, text: } turns for the whole episode.
    def call
      turns = []
      summary = []

      segments.each_with_index do |segment, index|
        $stderr.puts "[podcast] writing segment #{index + 1}/#{segments.size}: #{segment.label}"
        raw = chat(segment).ask(segment_prompt(segment, summary)).content
        segment_turns = parse(raw)
        raise "Segment '#{segment.label}' produced no dialogue lines" if segment_turns.empty?

        turns.concat(segment_turns)
        summary << "#{segment.label}: #{recap(segment_turns)}"
      end

      turns
    end

    def self.to_text(turns)
      turns.map { |turn| "#{turn[:speaker]}: #{turn[:text]}" }.join("\n")
    end

    private

    attr_reader :markdown, :preview, :history, :year, :week_number, :model

    def combined?
      preview.present?
    end

    def chat(segment)
      chat = model ? RubyLLM.chat(model: model) : RubyLLM.chat
      chat.with_instructions([ SYSTEM_PROMPT, rules_for(segment), (HISTORY_RULES if history) ].compact.join("\n"))
    end

    # The league history as a second source after the episode's own document, or nothing when there is none yet.
    def history_block
      return "" unless history

      "\nHere is the league history, earlier seasons only. It is background, not part of this week's story.\n\n<history>\n#{history}\n</history>\n"
    end

    def rules_for(segment)
      case segment.kind
      when :preview then @postseason_preview ? "#{preview_rules}\n#{POSTSEASON_RULES}" : preview_rules
      when :scoreboard then SCOREBOARD_RULES
      else @postseason_recap ? "#{REVIEW_RULES}\n#{POSTSEASON_RULES}" : REVIEW_RULES
      end
    end

    def preview_rules
      "#{PREVIEW_RULES}\n#{producer_notes}"
    end

    # The preview source's SHOW FORMAT and TONE sections, which sit between the run-of-show header and the opening.
    def producer_notes
      preview[/^## 🎙️ SHOW FORMAT.*?(?=^## 🎬)/m].to_s
    end

    # What the recapped week is called on air ("Week 13", "the Conference Championship").
    def label
      @recap_label.presence || "Week #{week_number}"
    end

    # What the previewed week is called on air: "Week 14", or "the Conference Championship" and the like.
    def preview_week
      @preview_label.presence || "Week #{preview[/^# .*BIG GAME BREAKDOWN — Week (\d+)/, 1] || (week_number.to_i + 1)}"
    end

    def team_headings
      @team_headings ||= markdown.scan(/^## (.+?) \(Coach:/).flatten
    end

    def game_headings
      @game_headings ||= preview.scan(/^## 🏈 GAME (\d+) OF (\d+): (.+)$/)
    end

    def segments
      @segments ||= @championship ? championship_segments : regular_segments
    end

    def regular_segments
      list = [ opening_segment ] + team_headings.map { |team| team_segment(team) }
      list << (combined? ? review_wrap_segment : closing_segment)
      list.concat(@scoreboard_only ? scoreboard_segments : preview_segments) if combined?
      list
    end

    def opening_segment
      narrator, co_host = PodcastShow::HOSTS
      Segment.new(
        label: "Opening", kind: :review, words: 350,
        instruction: <<~TEXT
          Write the cold open and the top of the show for "#{SHOW_NAME}", recapping #{label} of the #{year} season#{combined? ? (@scoreboard_only ? ", then the hosts' bet scoreboard later in the show" : ", then looking ahead to next week's games later in the show") : ''}.
          Follow this structure exactly:
          1. #{narrator[:name].split.first} opens with a brief, cinematic line setting the stakes for the week, then says:
             "Welcome back to #{SHOW_NAME}, I'm #{narrator[:name]}..."
          2. #{co_host[:name].split.first} follows up immediately with: "...and I'm #{co_host[:name]}."
          Then do a quick tour of the week: use "This Week at a Glance" and the CFP rankings and bowl projections to
          set the national stakes and tease what's coming (the recap first, then a look ahead at next week's games). Don't recap any game in detail; the team segments do that.
        TEXT
      )
    end

    def team_segment(team)
      return bye_segment(team) if bye?(team)

      next_up = if @scoreboard_only
        "Mention their next opponent in one short line only, no analysis or prediction."
      elsif combined?
        "Mention next week's opponent in one short line only; the preview later in the show covers it."
      else
        ""
      end
      Segment.new(
        label: team, kind: :review, words: 750,
        instruction: <<~TEXT
          Write the segment on #{team}'s #{label} game, using that team's section of the document.
          Make the Defining Storyline the centerpiece if the section lists one; otherwise tell how the game unfolded
          from the narrative, scoring by quarter and team stats, build to its biggest turning points, and give each
          host's own take. Work in the player of the game and one or two standout performers by name with their real
          numbers. Land on what this result means for #{team}'s season and standing. #{next_up}
          End the segment with a natural handoff, not a goodbye.
        TEXT
      )
    end

    # A team that had no game this week (a bye, common in the postseason) gets a short beat, not a game recap.
    def bye_segment(team)
      Segment.new(
        label: "#{team} (bye)", kind: :review, words: 130,
        instruction: <<~TEXT
          #{team} had a bye in #{label}: there was NO game, so do not describe or invent one. Give a short beat of a few
          lines: that they were off this week, where they stand (record, ranking, anything the section lists), and what
          is next for them according to the "Next Up" part of their section, in one line, with no analysis or prediction.
          End with a natural handoff, not a goodbye.
        TEXT
      )
    end

    # True when the document's section for this team says it had no game.
    def bye?(team)
      section = markdown.split(/^(?=## )/).find { |part| part.start_with?("## #{team} (Coach:") }
      section.to_s.include?("Bye week")
    end

    def closing_segment
      Segment.new(
        label: "Closing", kind: :review, words: 450,
        instruction: <<~TEXT
          Write the closing of the show: a quick "Around the Sun Belt" run through the other conference scores, a look
          at where the Sun Belt standings stand, then the Next Episode tease from the document as the last thing the
          hosts say about the future, then a short sign-off. Name the games in the tease and add no analysis,
          predictions or lines to it.
        TEXT
      )
    end

    # Combined episode: the recap ends here, with no tease and no sign-off, and pivots into the preview.
    def review_wrap_segment
      return postseason_wrap_segment if @postseason_recap

      Segment.new(
        label: "Review wrap-up", kind: :review, words: 450,
        instruction: <<~TEXT
          Write the end of the recap half: a quick "Around the Sun Belt" run through the other conference scores, a look
          at where the Sun Belt standings stand, the matchups between our coaches this week and the projected Sun Belt
          championship if the document has those sections. Ignore the document's "Next Episode" section completely.
          #{@scoreboard_only ? "Finish with a line that turns to the hosts' own scorecard, e.g. time to see how their bets did. Do NOT preview any games." : "Finish with a line that turns the show toward next week's games, e.g. that it's time to look ahead."} Do NOT
          sign off, and do not name or tease any upcoming episode.
        TEXT
      )
    end

    # Postseason recap ending: the CFP roundup and the bracket, with none of the regular-season round-up.
    def postseason_wrap_segment
      Segment.new(
        label: "Around the CFP", kind: :review, words: 400,
        instruction: <<~TEXT
          Write the end of the recap half: use the AROUND THE CFP section of the document to run through every College
          Football Playoff game of the week (the round, the teams, the winner and the score; one line is enough for our own
          team's game, which already had its segment) and what the results mean for the bracket. If that section isn't in the
          document, instead take a short look back at the week's biggest storyline. NO standings, NO poll or rankings, and
          ignore the document's "Next Episode" section completely.
          #{@scoreboard_only ? "Finish with a line that turns to the hosts' own scorecard, e.g. time to see how their bets did. Do NOT preview any games." : "Finish with a line that turns the show toward the next games, e.g. that it's time to look ahead."} Do NOT
          sign off, and do not name or tease any upcoming episode.
        TEXT
      )
    end

    def preview_segments
      [ preview_intro_segment ] + game_headings.map { |number, total, title| game_segment(number, total, title) } + [ preview_closing_segment ]
    end

    # The national championship episode: the title game, then the champion's road to it, then a sign-off. No team
    # round-up, no preview, no bets.
    def championship_segments
      narrator, co_host = PodcastShow::HOSTS
      [
        Segment.new(
          label: "Opening", kind: :review, words: 300,
          instruction: <<~TEXT
            Write the cold open of "#{SHOW_NAME}" for the NATIONAL CHAMPIONSHIP episode of the #{year} season. Follow this
            structure exactly:
            1. #{narrator[:name].split.first} opens with a brief, cinematic line about a national champion being crowned,
               then says: "Welcome back to #{SHOW_NAME}, I'm #{narrator[:name]}..."
            2. #{co_host[:name].split.first} follows up immediately with: "...and I'm #{co_host[:name]}."
            Then set up the show in a few lines: the title game first, then the champion's road to it. Name the champion
            only if the document's national championship section does. Don't recap the game yet.
          TEXT
        ),
        Segment.new(
          label: "The national championship game", kind: :review, words: 1300,
          instruction: <<~TEXT
            Write the segment on the national championship game, using THE NATIONAL CHAMPIONSHIP section of the document
            (the final score, the team stats, the players of the game and how the game went) and, where one of our teams
            played in it, that team's own section too. Tell how the game unfolded and build to its turning points, give
            each host's own take, work in the players of the game by name with their real numbers, and celebrate the
            champion. Do NOT walk through the earlier playoff games: the next segment does that. End with a natural handoff,
            not a goodbye.
          TEXT
        ),
        Segment.new(
          label: "The road to the title", kind: :review, words: 1000,
          instruction: <<~TEXT
            Write the segment "The Road to the Title", using the ROAD TO THE TITLE section of the document: go round by round
            through every playoff game the champion won to get here (the opponent, the score, home or on the road), and bring
            in the key moments from each game's "Key moments" text. Pick out the games and moments that stood out, let the
            hosts react to them, and build to the title game. Use only moments that are written in that section; never
            invent a play. End with a natural handoff, not a goodbye.
          TEXT
        ),
        Segment.new(
          label: "Sign-off", kind: :review, words: 250,
          instruction: <<~TEXT
            Write the end of the show: a warm sign-off in both hosts' voices that celebrates the champion and the season,
            ending on "see you next time" or similar and naming the show, "#{SHOW_NAME}". Do NOT name or tease any
            upcoming episode.
          TEXT
        )
      ]
    end

    # No preview (it was all previewed already): just the scoreboard of the hosts' bets, then the sign-off.
    def scoreboard_segments
      [
        Segment.new(
          label: "Bet scoreboard", kind: :scoreboard, words: 400,
          instruction: <<~TEXT
            The recap half just ended. Write the hosts' bet scoreboard with NO new welcome: use THE SCOREBOARD section of the
            document to review last week's bets game by game, in that order: the game and its final score, each host's bet
            and whether it hit or missed, and one short reaction each (about fifteen seconds a game). Then each host's season
            record. Do not preview any game.
          TEXT
        ),
        Segment.new(
          label: "Sign-off", kind: :scoreboard, words: 200,
          instruction: <<~TEXT
            Write the end of the whole episode: a short, warm sign-off in the hosts' voices ending on "see you next week" or
            similar, naming the show, "#{SHOW_NAME}". Do NOT name or tease any specific upcoming episode, preview any game
            or recap the bets.
          TEXT
        )
      ]
    end

    def preview_intro_segment
      Segment.new(
        label: "Preview: card and scoreboard", kind: :preview, words: 350,
        instruction: <<~TEXT
          The recap half just ended. Write the transition into the preview of #{preview_week} (call it that on air, never by a week number if it has a name), with
          NO new introductions or welcome, then these two beats:
          1. THE CARD: one sentence naming the #{game_headings.size} games on the board, in the document's order. No analysis.
          2. THE SCOREBOARD: use the document's "THE SCOREBOARD" section to review last week's bets game by game, in
             that order: the game and its final score, each host's bet and whether it hit or missed, and one short
             reaction each. About fifteen seconds a game. Then each host's season record.
          Keep it quick and get to Game 1 fast.
        TEXT
      )
    end

    def game_segment(number, total, title)
      finale = title.include?("THE FINALE")
      rivals = title.include?("RIVALS SHOWDOWN")
      words = if rivals then 1200 elsif finale then 900 else 500 end
      Segment.new(
        label: "Preview game #{number}: #{title}", kind: :preview, words: words,
        instruction: <<~TEXT
          Write the segment for Game #{number} of #{total}: #{title}, using that game's section of the document. Cover, in
          order, THE STAKES, THE FILM ROOM, THE QUARTERBACK DUEL and THE PICK, as the SHOW FORMAT notes describe.
          THE PICK is a real beat and the last thing said about the game: BOTH hosts state their exact bet out loud
          (use the wording of their Call lines in the document), give one fresh reason, and react to the other host's
          call. #{finale ? 'This is the finale: build the energy and let it run longer and bigger than the earlier games.' : 'Move through it tightly; the show builds toward the last game.'}
          #{rivals ? 'It is also a RIVALS SHOWDOWN between two of our coaches, so give both coaches\' perspectives and say what it means for each season and the rivalry.' : ''}
          #{number.to_i == 1 ? '' : 'Do not re-introduce the show; continue straight from the previous game.'}
        TEXT
      )
    end

    def preview_closing_segment
      heads_up = if preview.include?("ALSO ON THE BOARD (HEADS-UP ONLY)")
        <<~TEXT
          First the ALSO ON THE BOARD heads-up: for each game in that section name it with rankings, say when and where
          it's on (day only if it is Saturday, otherwise "this week"), and mention the line casually if one is listed.
          About ten seconds a game: no picks, no predictions, no analysis. Then
        TEXT
      else
        "There is no \"Also on the Board\" heads-up this time, so do not make one up or mention other games. Just "
      end
      Segment.new(
        label: "Preview closing", kind: :preview, words: 300,
        instruction: <<~TEXT
          Write the end of the whole episode. #{heads_up.squish} a short, warm sign-off in the hosts' voices ending on
          "see you next week" or similar, and naming the show, "#{SHOW_NAME}". Do NOT name or tease any specific upcoming
          episode and do not recap the bets.
        TEXT
      )
    end

    def segment_prompt(segment, summary)
      source = %i[preview scoreboard].include?(segment.kind) ? preview : markdown
      <<~PROMPT
        Here is the source document for this part of the show. It is the source of facts#{history ? " (the league history below is background only)" : ""}.

        <source>
        #{source}
        </source>
        #{history_block}
        #{summary.empty? ? "Nothing has been said yet; this is the first segment." : "Already covered in the show so far (do not repeat these points or re-introduce the hosts):\n- #{summary.join("\n- ")}"}

        SEGMENT TO WRITE NOW: #{segment.label}
        #{segment.instruction}
        Length: about #{segment.words} words of dialogue. Output only the dialogue lines.
      PROMPT
    end

    SPEAKER_LINE = /\A(ARLIS|TY):\s*(.+)\z/

    def parse(raw)
      raw.lines.filter_map do |line|
        match = SPEAKER_LINE.match(line.strip)
        { speaker: match[1], text: match[2] } if match
      end
    end

    # Keeps the running summary cheap: first sentence of the first couple of turns is enough to avoid repeats.
    def recap(turns)
      turns.first(4).map { |turn| turn[:text].split(/(?<=[.!?])\s/).first }.join(" ")
    end
  end
end
