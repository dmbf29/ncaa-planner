module BowlProjections
  # Extracts every row from a "bowl projections" screenshot — a full list
  # of every bowl's currently-projected matchup, taken during the season's
  # final couple of regular-season weeks (see BowlProjection's doc
  # comment), well before the real post-season schedule exists. Unlike
  # WeekScheduleExtractor, this screen doesn't print which week it was
  # captured on, so the caller (BowlProjectionsUpdatePage) has the user
  # pick that from a week selector rather than reading it off the image.
  #
  # A side shows "TBD" instead of a team when that slot's participant
  # hasn't been decided yet (e.g. a bye-week #1 seed's semifinal-hosting
  # bowl before the quarterfinals are played) — detected up front so it's
  # recorded as "no team yet" rather than flagged as an unmatched name.
  class Extractor
    include CollegeMatching

    TBD = "TBD".freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an expert at reading college football video game bowl projection screenshots and transcribing
      the exact values shown. Only report a value if you can actually see it — never guess.
    PROMPT

    def call(images)
      return { rows: [], colleges: colleges_json } if images.blank?

      rows = fetch_rows(images).map { |row| build_row(row) }
      { rows: rows, colleges: colleges_json }
    end

    private

    def chat
      RubyLLM.chat.with_instructions(SYSTEM_PROMPT)
    end

    def fetch_rows(images)
      names = college_names + [ TBD ]
      schema = RubyLLM::Schema.create do
        array :games, description: "One entry per row shown, in the order shown, across all images." do
          object do
            string :bowl_name, description: "The name shown in the GAME column, exactly as shown, e.g. 'Alamo Bowl' or 'Orange Bowl'."
            string :away_raw_name, description: "The team on the left side of the MATCHUP column, exactly as shown, " \
                                                 "excluding any ranking number prefix — or 'TBD' if that side shows no team yet."
            string :away_college_name, enum: names,
                   description: "The database college away_raw_name refers to — use your knowledge of team " \
                                "nicknames/abbreviations. Use '#{TBD}' if away_raw_name is 'TBD'. Only use " \
                                "'#{UNMATCHED}' if a team IS shown but none of the options are a plausible match."
            string :home_raw_name, description: "The team on the right side of the MATCHUP column, exactly as shown, " \
                                                 "excluding any ranking number prefix — or 'TBD' if that side shows no team yet."
            string :home_college_name, enum: names,
                   description: "Same matching rules as away_college_name, for home_raw_name."
          end
        end
      end
      raw = chat.with_schema(schema).ask(prompt, with: images).content
      Array(raw["games"]).select { |row| row.is_a?(Hash) }
    end

    def prompt
      "These screenshots together show a full list of projected bowl games, split across multiple images if " \
        "needed. Read every row's GAME and MATCHUP columns, top to bottom, across all images."
    end

    def build_row(row)
      bowl_name = row["bowl_name"]
      {
        bowl_name: bowl_name,
        cfp_round: CfpRoundInference.call(bowl_name),
        away_raw_name: row["away_raw_name"],
        away_college_id: resolve_side(row["away_raw_name"], row["away_college_name"]),
        home_raw_name: row["home_raw_name"],
        home_college_id: resolve_side(row["home_raw_name"], row["home_college_name"])
      }
    end

    def resolve_side(raw_name, matched_name)
      return nil if raw_name.blank? || raw_name.strip.casecmp?(TBD) || matched_name == TBD

      resolve_college(raw_name, matched_name)&.id
    end
  end
end
