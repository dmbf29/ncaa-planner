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

    # up_next is how the hosts should refer to this segment when the one before it hands off to it; the label is
    # a producer's name ("Preview game 2: ...") and not always something a person would say.
    Segment = Struct.new(:label, :kind, :instruction, :words, :up_next, keyword_init: true)

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
      - Some conferences are split into divisions. When the document groups a conference's standings by division, or
        says the division winners meet in the conference championship game, talk about division races and division
        titles: a team reaches the title game only by winning its division, never because it has one of the two best
        records in the conference. Never invent a division name or a team's division; use only those in the document.
      - The show is called "#{SHOW_NAME}" and is one continuous episode. Never say "Big Game Breakdown", never refer to
        the preview as a separate show or episode, and never name or tease any other episode. The look-ahead part of
        the show is just "the preview", "looking ahead", or "next week's games". The only thing the show may say about
        what comes after it is, in the sign-off when a segment asks for it, that the hosts are back next week to recap
        how those games played out.
      - Never say a calendar date or the name of a weekday, except "Saturday" for Saturday kickoffs. Say "this week"
        or "this weekend" instead, and "last week" for the week just played.

      WRITING FOR THE EAR
      - Output ONLY dialogue lines in the form `ARLIS: ...` or `TY: ...`, one turn per line. No headings, no
        markdown, no stage directions, no bracketed tags, no emoji.
      - Spell out numbers the way a person says them: "two hundred thirty-four yards", "twenty to fourteen",
        "four and four", "number ten in the country". Never read tables or lists; talk about them.
      - Say every number and score correctly the first time. No on-air self-corrections ("wait", "sorry", "let me back
        up", "I mean"): check which team has which score before saying it.
      - Say positions and school names as people do ("the quarterback", "App State"). Avoid abbreviations a voice
        might mangle, like "TFL", "YAC" or "INT"; say "tackles for loss", "yards after catch", "interception".
      - Turns are short, usually one to four sentences. The hosts react to each other, push back, finish each
        other's thoughts, and trade the lead. Avoid long monologues and avoid back-to-back turns that just agree.
      - Arlis is the narrative voice (stakes, emotion, how the game felt). Ty is the numbers and tactics voice (why
        it happened). Let each lean into that without being a caricature.

      BANTER (stats are welcome; the back-and-forth is what makes them fun)
      - No more than two or three numbers in one turn. After a turn heavy with stats, the other host reacts to it
        (surprise, a doubt, a joke, "wait, really?") or says what it means before the next number comes.
      - Every segment has at least a couple of real exchanges: a friendly disagreement, a teasing jab, a running joke,
        one host calling the other out, a "hold on, Ty". Keep them good-natured and about the football.
      - Never restate what the other host just said, and never open two turns in a row with the same words. Vary the
        stock phrases ("That is a...", "that's not a coincidence", "pin its ears back", "that's the story").
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

    PROVING_RULES = <<~TEXT.freeze
      THIS PART OF THE SHOW IS "SOMETHING TO PROVE", a quick forward-looking round of the coached teams before the games.
      Only use numbers, records, scores and rankings written in the source, with the group each was ranked against.
      Rankings and totals are backstage numbers: say them in plain studio language ("last in the Sun Belt in passing
      yards a game", "among the lowest-scoring teams in the country") and never a decimal read out digit by digit.
      Never use the words "model", "algorithm", "data" or "probability".
    TEXT

    POSTSEASON_RULES = <<~TEXT.freeze
      IT IS THE POSTSEASON (bowl games and the College Football Playoff). The regular season and its conference races
      are over: NEVER talk about conference standings, the conference championship race, the poll, rankings, "the
      top 25" or a team's ranking. Talk only about the games themselves, how they were won or lost, the bracket, and what
      a result means for what comes next. A team's record and its recent scores are fine.
      The Heisman Trophy has already been awarded (it comes after the conference championships): NEVER mention the
      Heisman, a Heisman candidate, Heisman hype or a player helping or hurting his Heisman case.
    TEXT

    NEUTRAL_SITE_RULES = <<~TEXT.freeze
      HOME AND AWAY: only a regular-season game and a College Football Playoff first-round game have a home team. A
      conference championship, a bowl game and every later playoff round is at a neutral site, so for those NEVER say
      home, away, hosting, visiting, "at home", "on the road", "home field", "home crowd" or "home cooking", and never
      call either team the home or road team. The source marks these games "vs" or "neutral site".
    TEXT

    CONFERENCE_CHAMPIONSHIP_RULES = <<~TEXT.freeze
      IT IS CONFERENCE CHAMPIONSHIP WEEK. The regular season is over and the title games settled the standings:
      NEVER talk about conference standings or the conference race. Only the teams that played in a title game are
      covered; do not mention a coached team that was not in one except in passing at most. Always name the
      conference when you talk about a title game ("the Sun Belt Championship Game").
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

    def initialize(year:, week_number:, markdown_path: nil, opener: false, proving_path: nil, preview_markdown_path: nil, history_path: nil, scoreboard_only: false, postseason_recap: false, conference_championship_recap: false, postseason_preview: false, championship: false, recap_label: nil,
                   preview_label: nil, model: nil)
      @markdown = markdown_path ? File.read(markdown_path) : ""
      @opener = opener
      @proving = File.read(proving_path) if proving_path
      @scoreboard_only = scoreboard_only
      @postseason_recap = postseason_recap
      @conference_championship_recap = conference_championship_recap
      @championship = championship
      @postseason_preview = postseason_preview
      @recap_label = recap_label
      @preview_label = preview_label
      @preview = File.read(preview_markdown_path) if preview_markdown_path
      @markdown = scrub_episode_name(@markdown) if @preview
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
        segment_turns = write_segment(segment, segment_prompt(segment, summary, turns.last(3), segments[index + 1]), turns.last(RECENT_TURNS))
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

    attr_reader :markdown, :preview, :proving, :history, :year, :week_number, :model

    def combined?
      preview.present?
    end

    # In a combined episode there is no separate Big Game Breakdown to send listeners to, but the recap document talks
    # as if there were (its sign-off, its "Next Episode" section, the "Next Up" notes) and the hosts read that out. So
    # the recap source is written without it.
    def scrub_episode_name(text)
      text.sub(/^- \*\*Segment \d+:\*\* Sign-Off.*\n/, "")
          .sub(/^## 👋 NEXT EPISODE.*?(?=^## |\z)/m, "")
          .gsub(/the Big Game Breakdown \(see the sign-off at the bottom\)/i, "the preview later in the show")
          .gsub(/Big Game Breakdown/i, "the preview later in the show")
    end

    FORBIDDEN_EPISODE_NAME = /big game breakdown/i
    REWRITES = 2
    # How many turns back a new turn is compared with when looking for repeats.
    RECENT_TURNS = 6

    # One model call per segment, checked before it is accepted: a draft that names the old episode, opens two turns
    # in a row with the same words, or says a sentence the hosts just said is sent back once or twice to be rewritten.
    def write_segment(segment, prompt, recent)
      conversation = chat(segment)
      segment_turns = parse(conversation.ask(prompt).content)
      REWRITES.times do
        problems = draft_problems(segment_turns, recent)
        break if problems.empty?

        $stderr.puts "[podcast] rewriting '#{segment.label}': #{problems.join('; ')}"
        segment_turns = parse(conversation.ask("Rewrite the whole segment with these problems fixed: #{problems.join('; ')}. Same length, same facts, dialogue lines only.").content).presence || segment_turns
      end
      # Last resort: never let the old episode's name reach the air.
      segment_turns.each { |turn| turn[:text] = turn[:text].gsub(FORBIDDEN_EPISODE_NAME, "the preview") } if combined?
      segment_turns
    end

    def draft_problems(segment_turns, recent)
      problems = []
      if combined? && (turn = segment_turns.find { |t| t[:text].match?(FORBIDDEN_EPISODE_NAME) })
        problems << "a host says \"Big Game Breakdown\" (\"#{turn[:text][0, 60]}...\"); there is no other show or episode, so refer only to the preview or next week's games"
      end
      all = recent + segment_turns
      (recent.size...all.size).each do |index|
        turn = all[index]
        if index.positive? && same_opening?(all[index - 1][:text], turn[:text])
          problems << "two turns in a row open with the same words (\"#{turn[:text][0, 50]}...\"); the second host must not repeat the first"
        end
        earlier = all[[ index - RECENT_TURNS, 0 ].max...index]
        if earlier.any? { |other| (spoken_sentences(other[:text]) & spoken_sentences(turn[:text])).any? }
          problems << "a turn repeats a sentence a host just said (\"#{turn[:text][0, 50]}...\"); every turn must add something new"
        end
      end
      problems.uniq
    end

    # The sentences of a turn, lowercased and stripped of punctuation. Short ones ("That's the story.") don't count.
    def spoken_sentences(text)
      text.split(/(?<=[.!?])\s+/).map { |sentence| sentence.downcase.scan(/[a-z0-9']+/) }.select { |words| words.size >= 7 }.map { |words| words.join(" ") }
    end

    # Same first four words, ignoring case and punctuation. Shorter turns are left alone ("Right." "Right.").
    def same_opening?(first, second)
      words = [ first, second ].map { |text| text.downcase.scan(/[a-z0-9']+/).first(4) }
      words.all? { |w| w.size == 4 } && words.first == words.last
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
      when :preview then [ preview_rules, NEUTRAL_SITE_RULES, (POSTSEASON_RULES if @postseason_preview) ].compact.join("\n")
      when :scoreboard then SCOREBOARD_RULES
      when :proving then PROVING_RULES
      else
        [ REVIEW_RULES, (NEUTRAL_SITE_RULES if @postseason_recap || @conference_championship_recap),
          (POSTSEASON_RULES if @postseason_recap), (CONFERENCE_CHAMPIONSHIP_RULES if @conference_championship_recap) ].compact.join("\n")
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
      @segments ||= if @championship then championship_segments elsif @opener then opener_segments else regular_segments end
    end

    def regular_segments
      list = [ opening_segment ] + game_segments + recap_tail_segments
      list.concat(@scoreboard_only ? scoreboard_segments : preview_segments) if combined?
      list
    end

    # Everything after the game recaps, in the run-of-show's own order: the rest of the conference, the injury and
    # recruiting stops when there is fresh material, then the poll. The last of them is also what ends the recap half
    # (it hands off to the preview or scoreboard) or, with no second half, the whole show.
    def recap_tail_segments
      if @postseason_recap || @conference_championship_recap
        side_segments + [ combined? ? review_wrap_segment : closing_segment ]
      else
        [ around_conference_segment ] + side_segments + [ poll_watch_segment ]
      end
    end

    def around_conference_segment
      Segment.new(
        label: "Around the Sun Belt", kind: :review, words: 400, up_next: "a quick lap around the rest of the Sun Belt",
        instruction: <<~TEXT
          Write the "Around the Sun Belt" segment: a quick run through the other conference scores (the document's
          AROUND THE SUN BELT section), then where the Sun Belt standings stand, talking about the division races, and
          the projected Sun Belt championship if the document has that section. Do not preview next week's games or
          the matchups between our coaches; the preview later in the show covers those. You own the standings: the game segments only touched on them, so go through the division races properly here, once, without repeating the game segments' lines. Ignore the document's "Next
          Episode" section completely.
        TEXT
      )
    end

    # The document names it "Top 25 Poll Watch" or "CFP Rankings Watch" depending on the week.
    POLL_WATCH = /(Top 25 Poll Watch|CFP Rankings Watch) — (.+)$/

    def poll_watch_segment
      found = markdown.match(/^- \*\*Segment \d+:\*\* #{POLL_WATCH}/)
      name = found ? found[1] : "Top 25 Poll Watch"
      guidance = found && found[2]
      Segment.new(
        label: name, kind: :review, words: 300, up_next: "a look at the national rankings",
        instruction: <<~TEXT
          Write the "#{name}" segment, the last stop of the recap half. #{"The document's guidance: #{guidance}" if guidance}
          Use the document's rankings (its TOP 25 or CFP rankings section and the "This Week at a Glance" table): where our
          teams sit, who moved, who fell out or is knocking on the door, and what is at stake nationally. Name only teams
          and ranks the document lists, and don't read out the poll. Don't go back over the standings or a team's game; you own only the rankings.
          #{combined? ? '' : "Then give the Next Episode tease from the document as the last thing the hosts say about the future, then a short sign-off. Name the games in the tease and add no analysis, predictions or lines to it."}
        TEXT
      )
    end

    # The run-of-show lines the document adds only when there is fresh material: "Injury Report" and "Recruitment
    # Trail", each with its own guidance. They get a real segment (the teams' sections only mention them in passing),
    # so the opening can tease them without promising something the show never delivers.
    SIDE_SEGMENTS = { "Injury Report" => 300, "Recruitment Trail" => 150 }.freeze

    def side_segments
      SIDE_SEGMENTS.filter_map do |name, words|
        guidance = markdown[/^- \*\*Segment \d+:\*\* #{name} — (.+)$/, 1]
        next unless guidance

        Segment.new(
          label: name, kind: :review, words: words,
          instruction: <<~TEXT
            Write the "#{name}" segment, a short stop after the game recaps. The document's guidance: #{guidance}
            Use ONLY what the teams' "#{name == 'Injury Report' ? '🚑 Injury Report' : '🖊️ Recruitment Trail'}" sections list, with their real names and numbers; invent nothing.
          TEXT
        )
      end
    end

    # One segment per game, not per team: a game between two of our coaches shows up in both teams' sections, and
    # writing a segment for each told it twice. Those rivals games are told once, from both sides, and lead the show.
    def game_segments
      done = []
      rivals, others = [], []
      team_headings.each do |team|
        next if done.include?(team)

        opponent = coached_opponent(team)
        done << team
        if opponent
          done << opponent
          rivals << head_to_head_segment(team, opponent)
        else
          others << team_segment(team)
        end
      end
      rivals + others
    end

    # The other coached team this team's game was against, or nil.
    def coached_opponent(team)
      opponent = team_section(team).to_s[/^- [WL] \d+-\d+ (?:vs|@) (.+?)(?: \(neutral site\))? \[fellow user-coached team\]/, 1]
      opponent if opponent && team_headings.include?(opponent)
    end

    def team_section(team)
      markdown.split(/^(?=## )/).find { |part| part.start_with?("## #{team} (Coach:") }
    end

    def head_to_head_segment(team, opponent)
      Segment.new(
        label: "#{team} vs #{opponent}", kind: :review, words: 1300,
        instruction: <<~TEXT
          #{team} and #{opponent} played EACH OTHER in #{label}, and both are teams of ours. Write ONE segment on this
          single game, using both teams' sections of the document (they describe the same game from each side). Tell
          the game once: do not retell it from the second team's side or write a second segment on it. Make the Defining
          Storyline the centerpiece if a section lists one; otherwise build to the game's turning points. Cover both
          coaches' perspectives, work in the players of the game and standout performers from BOTH sides by name with
          their real numbers, give each host's own take, and land on what it means for each team's season and the
          rivalry. #{owns_note} #{@scoreboard_only ? "Mention each team's next opponent in one short line only, no analysis or prediction." : "Mention each team's next opponent in one short line only."}
          End the segment with a natural handoff, not a goodbye.
        TEXT
      )
    end

    # Each topic has one owner, so the hosts don't say the same thing in every segment: the division races and the
    # conference standings belong to "Around the Sun Belt", poll movement to the poll segment. Postseason and title-game
    # weeks have no such segments (and no standings talk at all), so they get no note.
    def owns_note
      return "" if @postseason_recap || @conference_championship_recap

      "Do NOT go through the division race, conference standings or poll movement here (a team's record and one passing clause is fine): the Around the Sun Belt and #{poll_watch_name} segments later in the show cover those."
    end

    def poll_watch_name
      markdown[/^- \*\*Segment \d+:\*\* (Top 25 Poll Watch|CFP Rankings Watch)/, 1] || "Top 25 Poll Watch"
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
          set the national stakes and tease what's coming (the recap first, then a look ahead at next week's games).
          After the game recaps the show also has, in this order: #{recap_tail_segments.map(&:label).join(', ')}, then the look ahead at next week's games. You may tease those in one short line, in that order. Promise NOTHING else: no "what it means for the division races" or any other segment that is not in this plan.
          Don't read final scores or stat lines here and don't recap any game: tease the storylines and stakes, because the game segments give the scores.
          Finish with ONE short handoff line into the first game recap and nothing after it. No "but first", no "let's get into it" lines on top of it.
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
          numbers. Land on what this result means for #{team}'s season, in a sentence or two. #{owns_note} #{next_up}
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
      team_section(team).to_s.include?("Bye week")
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

    # Combined episode, postseason and championship weeks only (the regular season ends its recap with
    # poll_watch_segment): the recap ends here, with no tease and no sign-off, and pivots into the second half.
    def review_wrap_segment
      @postseason_recap ? postseason_wrap_segment : championship_week_wrap_segment
    end

    # Conference championship week: the title games are the whole recap, so no standings and no regular-season round-up.
    def championship_week_wrap_segment
      Segment.new(
        label: "Review wrap-up", kind: :review, words: 300,
        instruction: <<~TEXT
          Write the end of the recap half: a quick run through the other conference scores in the document, if it lists
          any, and what the title game results mean for the national picture (the rankings and bowl projections the
          document lists). NO conference standings. Ignore the document's "Next Episode" section completely.
          #{@scoreboard_only ? "Finish with a line that turns to the hosts' own scorecard, e.g. time to see how their bets did. Do NOT preview any games." : "Finish with a line that turns the show toward the next games, e.g. that it's time to look ahead."} Do NOT
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

    # The season opener: no recap half (nothing has been played yet), just a welcome, the card, one segment per game
    # and the sign-off. The first games of the season are previewed from the preview source alone.
    def opener_segments
      [ opener_intro_segment, (proving_segment if proving) ].compact + game_headings.map { |number, total, title| game_segment(number, total, title) } + [ preview_closing_segment ]
    end

    def opener_intro_segment
      narrator, co_host = PodcastShow::HOSTS
      Segment.new(
        label: "Opener: welcome and card", kind: :preview, words: (proving ? 300 : 450),
        instruction: <<~TEXT
          This is the first show of the #{year} season and nothing has been played yet. Write the cold open and the top of
          the show, with these beats in order:
          1. #{narrator[:name].split.first} opens with a brief, cinematic line about the season finally kicking off, then
             says: "Welcome back to #{SHOW_NAME}, I'm #{narrator[:name]}..."
          2. #{co_host[:name].split.first} follows up immediately with: "...and I'm #{co_host[:name]}."
          3. #{proving ? "One or two lines on what the season opener means, no more: the next segment is \"Something to Prove\", which carries the team-by-team talk." : "A few lines of what the season opener means for these teams (use only the last-season records, new-conference notes and rankings written in the document; the league history is background)."} Do not recap last season game by game and do not talk about games that are not on this card.
          4. THE CARD: one sentence naming the #{game_headings.size} games on the board, in the document's order. No analysis.
          #{proving ? "End by turning to \"Something to Prove\"." : "Keep it quick and get to Game 1 fast."} Call the week #{preview_week}.
        TEXT
      )
    end

    # "Something to Prove": the one thing each coached team has to answer this season, from the proving fact sheet.
    def proving_segment
      Segment.new(
        label: "Something to Prove", kind: :proving, words: 400,
        instruction: <<~TEXT
          The welcome and the card just ended. With NO new welcome, write the segment "Something to Prove": for each team
          in the document, in the document's order, the ONE thing it has to prove or fix this season, about twenty-five
          seconds per team with both hosts weighing in. Name the segment out loud once ("Something to Prove") and tie the
          last line to Game 1 so the show moves on. Rules for this segment:
          - Choose the thing from the document's facts; say the ranking with the group it was ranked against, exactly as the
            document words it ("in the Sun Belt", "among 138 schools"). Never say "nationally" for a Sun Belt-only ranking.
          - Do not recap last season, do not talk about championships won, and do not read a list of losses: pick the
            pattern. Sound forward-looking: the question this season has to answer.
          - A team new to a conference, or that moved to another division, gets its move named once, inside its own beat,
            along with what the new division means (only the division winners reach the conference championship game).
          - A departed player is at most one clause, never a roster review.
          - Do not preview any game or make any pick here; the game segments do that.
        TEXT
      )
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
          label: "Bet scoreboard", kind: :scoreboard, words: 400, up_next: "the hosts' own bet scoreboard (how their bets did; do not preview any games)",
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
        up_next: "the look ahead at #{preview_week}'s games, starting with last week's bet scoreboard",
        instruction: <<~TEXT
          The recap half just ended and its last line already turned the show toward the preview, so write NO separate
          transition and NO new introductions or welcome. Open straight into these two beats:
          1. THE CARD: one sentence that names the preview of #{preview_week} (call it that on air, never by a week number if it has a name)
             and the #{game_headings.size} games on the board, in the document's order. No analysis. A conference
             championship game is named with its conference ("the Sun Belt Championship Game"), never just "the conference championship".
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
        label: "Preview game #{number}: #{title}", kind: :preview, words: words, up_next: "Game #{number}: #{title.sub(/ — .*/, '')}",
        instruction: <<~TEXT
          Write the segment for Game #{number} of #{total}: #{title}, using that game's section of the document. Cover, in
          order, THE STAKES, THE FILM ROOM, THE QUARTERBACK DUEL and THE PICK, as the SHOW FORMAT notes describe.
          THE PICK is a real beat and the last thing said about the game: BOTH hosts state their exact bet out loud
          (use the wording of their Call lines in the document), give one fresh reason, and react to the other host's
          call. #{finale ? 'This is the finale: build the energy and let it run longer and bigger than the earlier games.' : 'Move through it tightly; the show builds toward the last game.'}
          #{rivals ? 'It is also a RIVALS SHOWDOWN between two of our coaches, so give both coaches\' perspectives and say what it means for each season and the rivalry.' : ''}
          #{title.include?('CHAMPIONSHIP GAME') ? 'This is a conference title game: say which conference it is for when you introduce it, and treat it as a neutral-site game (no home or road team).' : ''}
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
        label: "Preview closing", kind: :preview, words: 300, up_next: "the rest of the board and the sign-off",
        instruction: <<~TEXT
          Write the end of the whole episode. #{heads_up.squish} the sign-off, in this order:
          1. THE TEASE: tell listeners the hosts are back next week to recap how these games played out, naming the one
             or two biggest games from the card (the Rivals Showdown if there is one). Name the games ONCE, here, and
             don't list them again in the exit line. Names only: no analysis, no
             predictions, no lines, and do not recap the bets. Say it as "next week we'll be back to tell you how it
             all went", never as a separate show or episode.
          2. THE EXIT: end with a short, warm, fun exit line in the hosts' voices that names the show, "#{SHOW_NAME}".
             Make it feel like these two, a last jab or joke between them, not a generic "see you next time".
        TEXT
      )
    end

    def segment_prompt(segment, summary, lead_in = [], following = nil)
      source = if segment.kind == :proving then proving elsif %i[preview scoreboard].include?(segment.kind) then preview else markdown end
      <<~PROMPT
        Here is the source document for this part of the show. It is the source of facts#{history ? " (the league history below is background only)" : ""}.

        <source>
        #{source}
        </source>
        #{history_block}
        #{summary.empty? ? "Nothing has been said yet; this is the first segment." : "Already covered in the show so far (do not repeat these points, or the stat lines, records and standings already given, and do not re-introduce the hosts; bring a number back only to make a NEW point):\n- #{summary.join("\n- ")}"}

        SEGMENT TO WRITE NOW: #{segment.label}
        #{segment.instruction}
        #{seam_notes(lead_in, following)}
        Length: about #{segment.words} words of dialogue. Output only the dialogue lines.
      PROMPT
    end

    # Segments are written one call at a time, so each one is told what the show just said and what comes next.
    # Without it a segment's handoff guesses the next topic, and the next segment announces its topic all over again.
    # The outgoing segment owns the handoff; the incoming one opens straight into content.
    def seam_notes(lead_in, following)
      notes = []
      if lead_in.any?
        notes << "The show so far just ended on these lines, which already handed off to this segment. Continue straight from " \
                 "them: do NOT announce or introduce this segment's topic again (no \"let's talk about\", \"next up\", \"now to\"). " \
                 "Open with a reaction or the first real point.\n#{self.class.to_text(lead_in)}"
      end
      if following
        notes << "UP NEXT in the show: #{following.up_next || "\"#{following.label}\""}. End this segment with ONE short handoff line " \
                 "(a single sentence from one host) that points only to that. Do not announce or tease anything else, and don't say goodbye."
      end
      notes.join("\n")
    end

    SPEAKER_LINE = /\A(ARLIS|TY):\s*(.+)\z/

    def parse(raw)
      raw.lines.filter_map do |line|
        match = SPEAKER_LINE.match(line.strip)
        { speaker: match[1], text: match[2] } if match
      end
    end

    # Keeps the running summary cheap: the first sentence of a handful of turns spread across the segment, which is
    # enough for the segments after it to see what was already said.
    def recap(turns)
      turns.each_slice([ turns.size / 6, 1 ].max).map(&:first).first(6).map { |turn| turn[:text].split(/(?<=[.!?])\s/).first }.join(" ")
    end
  end
end
