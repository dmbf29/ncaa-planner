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
  # Both the matchup/date call and the time/score call use that same
  # enum-matched name as their join key, so merging the two calls' rows is
  # an exact string match rather than a fuzzy one.
  class WeekScheduleExtractor
    UNMATCHED = "Unmatched".freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an expert at reading college football video game weekly schedule screenshots and transcribing
      the exact values shown. Only report a value if you can actually see it — never guess.
    PROMPT

    def call(images)
      return { week_number: nil, rows: [], colleges: colleges_json } if images.blank?

      week_number = fetch_week_number(images)
      matchups = fetch_matchups(images)
      results_by_key = fetch_results(images).index_by { |row| key_for(row) }

      rows = matchups.map { |row| build_row(row, results_by_key[key_for(row)]) }

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
      Array(raw["games"]).select { |row| row.is_a?(Hash) }
    end

    def fetch_results(images)
      names = college_names
      schema = RubyLLM::Schema.create do
        array :games, description: "One entry per row — match rows up by the same away/home college names." do
          object do
            string :away_college_name, enum: names, description: "Same matching rules as in the matchup table — used only to line this row up"
            string :home_college_name, enum: names, description: "Same matching rules as in the matchup table — used only to line this row up"
            string :time_of_day, required: false,
                   description: "Exactly as shown in TIME(ET)/RESULT when it's a kickoff time, e.g. '4:00 PM'. " \
                                "Leave unset if that column shows a final score instead."
            integer :away_score, required: false,
                    description: "First number in TIME(ET)/RESULT when it shows a final score " \
                                 "(e.g. 38 in 'LTU 38, M-OH 6' — the away team's number always comes first). " \
                                 "Leave unset if a kickoff time is shown instead."
            integer :home_score, required: false,
                    description: "Second number in TIME(ET)/RESULT when it shows a final score. Leave unset if a kickoff time is shown instead."
          end
        end
      end
      raw = chat.with_schema(schema).ask(result_prompt, with: images).content
      Array(raw["games"]).select { |row| row.is_a?(Hash) }
    end

    def matchup_prompt
      "These screenshots together show one week's full schedule, split across multiple images if needed. " \
        "Read every row in the MATCHUP and DATE columns, top to bottom, across all images."
    end

    def result_prompt
      "These screenshots together show one week's full schedule. For each row, read the TIME(ET)/RESULT " \
        "column: it shows a kickoff time if the game hasn't been played, or a final score (two team " \
        "abbreviations each with a number, away team's number first) if it has."
    end

    def key_for(row)
      [ row["away_college_name"], row["home_college_name"] ]
    end

    def build_row(matchup, result)
      away_name = matchup["away_college_name"]
      home_name = matchup["home_college_name"]

      {
        away_raw_name: matchup["away_raw_name"],
        away_college_id: resolve_college(away_name)&.id,
        home_raw_name: matchup["home_raw_name"],
        home_college_id: resolve_college(home_name)&.id,
        month: matchup["month"],
        day: matchup["day"],
        time_of_day: result&.fetch("time_of_day", nil),
        away_score: result&.fetch("away_score", nil),
        home_score: result&.fetch("home_score", nil)
      }
    end

    def resolve_college(name)
      return nil if name.blank? || name == UNMATCHED

      colleges_by_name[name]
    end

    def colleges
      @colleges ||= College.order(:name).to_a
    end

    def colleges_by_name
      @colleges_by_name ||= colleges.index_by(&:name)
    end

    def college_names
      @college_names ||= colleges.map(&:name) + [ UNMATCHED ]
    end

    def colleges_json
      colleges.map { |college| { id: college.id, name: college.name } }
    end
  end
end
