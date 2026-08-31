module BowlProjections
  # Extracts every row from a "bowl projections" screenshot — a full list
  # of every bowl's currently-projected matchup, taken during the season's
  # final couple of regular-season weeks (see BowlProjection's doc
  # comment), well before the real post-season schedule exists. Unlike
  # WeekScheduleExtractor, this screen doesn't print which week it was
  # captured on, so the caller (BowlProjectionsUpdatePage) has the user
  # pick that from a week selector rather than reading it off the image.
  #
  # Extracted ONE IMAGE AT A TIME (results merged after), each image split
  # into two calls joined by row_number — matchups (bowl name + both
  # teams, all required) and date/time (all optional) — exactly like
  # WeekScheduleExtractor's two-call split. Empirically, giving a single
  # call ALL of a long, multi-image list at once is unreliable: against a
  # real ~37-row/3-image list, repeated identical requests sometimes
  # returned an empty result and other times silently truncated partway
  # through (e.g. stopping cleanly after row 20 of 37, mid-list, with no
  # error) — a max-output/complexity ceiling being hit, not corrupted
  # input (confirmed byte-identical images on every attempt). Splitting
  # the optional fields into their own call wasn't sufficient by itself;
  # capping each call to one image's worth of rows was what actually
  # fixed it. dedupe below then guards against the same bowl appearing on
  # more than one screenshot due to overlap between captures.
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

      rows = Array(images).flat_map { |image| extract_from_image(image) }
      { rows: dedupe(rows), colleges: colleges_json }
    end

    private

    def extract_from_image(image)
      matchups = fetch_matchups([ image ])
      dates_by_row_number = fetch_dates([ image ]).index_by { |row| row["row_number"] }
      matchups.map { |row| build_row(row, dates_by_row_number[row["row_number"]]) }
    end

    def chat
      RubyLLM.chat.with_instructions(SYSTEM_PROMPT)
    end

    def fetch_matchups(images)
      names = college_names + [ TBD ]
      schema = RubyLLM::Schema.create do
        array :games, description: "One entry per row shown in the GAME/MATCHUP columns, in the order shown, across all images." do
          object do
            integer :row_number, description: "This row's position counting from 1 at the top, top to bottom across all images."
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
      raw = chat.with_schema(schema).ask(matchup_prompt, with: images).content
      Array(raw["games"]).select { |row| row.is_a?(Hash) && row["row_number"].is_a?(Integer) }
    end

    def fetch_dates(images)
      schema = RubyLLM::Schema.create do
        array :games, description: "One entry per row shown in the DATE AND TIME column, in the same top-to-bottom order as the matchup table." do
          object do
            integer :row_number, description: "This row's position counting from 1 at the top — must match the same row's position in the matchup table."
            integer :month, required: false, description: "Month number from the DATE AND TIME column, e.g. 12 for 'Dec 26'. Leave unset if no date is shown."
            integer :day, required: false, description: "Day of month from the DATE AND TIME column, e.g. 26 for 'Dec 26'. Leave unset if no date is shown."
            string :time_of_day, required: false,
                   description: "Kickoff time exactly as shown, e.g. '7:30 PM'. Leave unset if no time is shown."
          end
        end
      end
      raw = chat.with_schema(schema).ask(date_prompt, with: images).content
      Array(raw["games"]).select { |row| row.is_a?(Hash) && row["row_number"].is_a?(Integer) }
    end

    def matchup_prompt
      "This screenshot shows part of a list of projected bowl games. Read every row's GAME and MATCHUP " \
        "columns, top to bottom."
    end

    def date_prompt
      "This screenshot shows part of a list of projected bowl games. For each row, read the DATE AND TIME " \
        "(ET) column."
    end

    # Belt-and-suspenders against the model still reporting an overlapping
    # row twice despite the prompt above — same (bowl, matchup) reported
    # more than once collapses to a single row rather than showing the
    # user two confusing look-alike rows to review.
    def dedupe(rows)
      rows.uniq { |row| [ row[:bowl_name], row[:away_college_id], row[:home_college_id] ] }
    end

    def build_row(matchup, date)
      bowl_name = matchup["bowl_name"]
      {
        bowl_name: bowl_name,
        cfp_round: CfpRoundInference.call(bowl_name),
        away_raw_name: matchup["away_raw_name"],
        away_college_id: resolve_side(matchup["away_raw_name"], matchup["away_college_name"]),
        home_raw_name: matchup["home_raw_name"],
        home_college_id: resolve_side(matchup["home_raw_name"], matchup["home_college_name"]),
        month: date&.fetch("month", nil),
        day: date&.fetch("day", nil),
        time_of_day: date&.fetch("time_of_day", nil)
      }
    end

    def resolve_side(raw_name, matched_name)
      return nil if raw_name.blank? || raw_name.strip.casecmp?(TBD) || matched_name == TBD

      resolve_college(raw_name, matched_name)&.id
    end
  end
end
