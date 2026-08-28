module ScheduleStats
  # Extracts a week's full schedule (every game shown — not just coached
  # teams', since Colleges exist as "league context" even when not coached,
  # per CLAUDE.md) from however many screenshots it takes to show the whole
  # week.
  #
  # Team names on this screen are often nicknames/abbreviations that don't
  # match the DB's college.name verbatim (e.g. "Appalachian State" is
  # stored as "App St.", "Jacksonville State" as "Jax State"). Rather than
  # fuzzy-matching those in Ruby — brittle, since the abbreviation style is
  # inconsistent across colleges — away/home college name fields are
  # enum-constrained to the real college list (plus an "Unmatched"
  # sentinel), letting the model use its own knowledge of team nicknames.
  # Empirically this works: a 144-value enum on a required field compiles
  # fine and correctly resolved every nickname case tried, since enum
  # cardinality on one field is a different complexity class from the
  # "too many optional fields" limit documented on PlayerCategoryExtractor
  # (that's about combinatorial grammar branching across independently
  # optional fields, not closed-vocabulary constraints).
  #
  # Rows are matched between the two calls by row_number — each row's
  # top-to-bottom position, reported explicitly by the model in both calls
  # — rather than by re-transcribed team name text. An earlier version
  # joined on (away_raw_name, home_raw_name); that's fragile because the two
  # calls transcribe those names independently, and any drift between them
  # (whitespace, abbreviation choice, or just more transcription errors
  # creeping in on later rows of a long list) makes the join silently miss
  # for that one row — its time/score data is quietly dropped with no
  # error. row_number doesn't have that failure mode since it's just "which
  # row is this," not free-text transcription.
  class WeekScheduleExtractor
    include CollegeMatching

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an expert at reading college football video game weekly schedule screenshots and transcribing
      the exact values shown. Only report a value if you can actually see it — never guess.
    PROMPT

    def call(images)
      return { week_number: nil, rows: [], colleges: colleges_json } if images.blank?

      week_number = fetch_week_number(images)
      matchups = fetch_matchups(images)
      results_by_row_number = fetch_results(images).index_by { |row| row["row_number"] }

      rows = matchups.map { |row| build_row(row, results_by_row_number[row["row_number"]]) }

      { week_number: week_number, rows: rows, colleges: colleges_json }
    end

    private

    def chat
      RubyLLM.chat.with_instructions(SYSTEM_PROMPT)
    end

    def fetch_week_number(images)
      schema = RubyLLM::Schema.create do
        integer :week_number, description: "The number shown after 'WEEK' in the top-left header, e.g. 0 for 'WEEK 0'"
      end
      raw = chat.with_schema(schema).ask("What week number is shown at the top of these schedule screenshots?", with: images).content
      raw["week_number"]
    end

    def fetch_matchups(images)
      names = college_names
      schema = RubyLLM::Schema.create do
        array :games, description: "One entry per row in the MATCHUP column, in the order shown." do
          object do
            integer :row_number, description: "This row's position counting from 1 at the top, top to bottom across all images — must line up with the same row's position in the TIME(ET)/RESULT reading."
            string :bowl_name, required: false,
                   description: "The name shown in a GAME column to the left of the matchup, if this screenshot has " \
                                "one (e.g. 'Alamo Bowl', 'CFP First Round', 'Cotton Bowl'). Leave unset if there is " \
                                "no such column — a regular-season schedule screen only has MATCHUP and DATE."
            string :away_raw_name, description: "The team on the left of 'at' in the MATCHUP column, exactly as shown"
            string :away_college_name, enum: names,
                   description: "The database college that away_raw_name refers to — use your knowledge of team " \
                                "nicknames/abbreviations (e.g. 'Appalachian State' -> 'App St.'). Only use " \
                                "'#{UNMATCHED}' if none of the options are a plausible match."
            string :home_raw_name, description: "The team on the right of 'at' in the MATCHUP column, exactly as shown"
            string :home_college_name, enum: names,
                   description: "The database college that home_raw_name refers to, same matching rules as away_college_name."
            integer :month, description: "Month number from the DATE column, e.g. 8 for 'Aug 29'"
            integer :day, description: "Day of month from the DATE column, e.g. 29 for 'Aug 29'"
          end
        end
      end
      raw = chat.with_schema(schema).ask(matchup_prompt, with: images).content
      Array(raw["games"]).select { |row| row.is_a?(Hash) && row["row_number"].is_a?(Integer) }
    end

    # first_score/second_score and first_score_is_away are read as plain
    # printed values, not "away_score"/"home_score" — the two numbers in
    # TIME(ET)/RESULT are printed in *winning* order (e.g. both "MIA 41,
    # FCSSE 0" and, from the loser's side of a different row, "PITT 31, UCF
    # 19" put the winner's abbreviation-and-score first), not fixed
    # away-then-home order, confirmed against real screenshots. Asking the
    # model which side the first number belongs to (rather than assuming a
    # fixed order) is what actually resolves it correctly either way.
    def fetch_results(images)
      schema = RubyLLM::Schema.create do
        array :games, description: "One entry per row in the TIME(ET)/RESULT column, in the same top-to-bottom order as the matchup table." do
          object do
            integer :row_number, description: "This row's position counting from 1 at the top — must match the same row's position in the matchup table."
            string :time_of_day, required: false,
                   description: "Exactly as shown in TIME(ET)/RESULT when it's a kickoff time, e.g. '4:00 PM'. " \
                                "Leave unset if that column shows a final score instead."
            integer :first_score, required: false,
                    description: "The first number shown in TIME(ET)/RESULT when it shows a final score, e.g. " \
                                 "38 in 'LTU 38, M-OH 6' — read it exactly as printed, do not guess whose score " \
                                 "it is. Leave unset if a kickoff time is shown instead."
            integer :second_score, required: false,
                    description: "The second number shown in TIME(ET)/RESULT when it shows a final score, e.g. " \
                                 "6 in 'LTU 38, M-OH 6'. Leave unset if a kickoff time is shown instead."
            boolean :first_score_is_away, required: false,
                    description: "True if the first team abbreviation/score shown in TIME(ET)/RESULT is the AWAY " \
                                 "team (the one on the left of 'at' in this row's matchup), false if it's the HOME " \
                                 "team. Leave unset if a kickoff time is shown instead."
          end
        end
      end
      raw = chat.with_schema(schema).ask(result_prompt, with: images).content
      Array(raw["games"]).select { |row| row.is_a?(Hash) && row["row_number"].is_a?(Integer) }
    end

    def matchup_prompt
      "These screenshots together show one week's full schedule, split across multiple images if needed. " \
        "Read every row in the GAME (if present), MATCHUP, and DATE columns, top to bottom, across all images."
    end

    def result_prompt
      "These screenshots together show one week's full schedule. For each row, read the TIME(ET)/RESULT " \
        "column: it shows a kickoff time if the game hasn't been played, or a final score (two team " \
        "abbreviations each with a number) if it has."
    end

    def build_row(matchup, result)
      away_raw = matchup["away_raw_name"]
      home_raw = matchup["home_raw_name"]
      scores = resolved_scores(result)

      {
        bowl_name: matchup["bowl_name"],
        away_raw_name: away_raw,
        away_college_id: resolve_college(away_raw, matchup["away_college_name"])&.id,
        home_raw_name: home_raw,
        home_college_id: resolve_college(home_raw, matchup["home_college_name"])&.id,
        month: matchup["month"],
        day: matchup["day"],
        time_of_day: result&.fetch("time_of_day", nil),
        away_score: scores[:away_score],
        home_score: scores[:home_score]
      }
    end

    def resolved_scores(result)
      first_score = result&.fetch("first_score", nil)
      second_score = result&.fetch("second_score", nil)
      first_is_away = result&.fetch("first_score_is_away", nil)
      return { away_score: nil, home_score: nil } if first_score.nil? || second_score.nil? || first_is_away.nil?

      first_is_away ? { away_score: first_score, home_score: second_score } : { away_score: second_score, home_score: first_score }
    end
  end
end
