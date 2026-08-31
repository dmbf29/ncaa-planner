module NilSpend
  # Extracts a conference-wide NIL spend table (team total + breakdown by
  # position group) from however many screenshots it takes to show the
  # whole conference. There's no coached-team filtering — every row shown
  # gets extracted, since Colleges are league context even when not
  # coached, per CLAUDE.md (and per the user, scraping every conference's
  # full roster just to compute this isn't worth it for a once-a-season
  # upload).
  #
  # Team names get the same enum-constrained matching used elsewhere, with
  # the same fix: the enum field alone is unsafe — it consistently
  # truncates a correct longer answer down to a shorter college name
  # that's also a valid enum value and an exact prefix of the right one
  # ("Arkansas State" -> "Arkansas", "Ohio State" -> "Ohio"), so
  # college_raw_name (plain text, unaffected) is checked for an exact
  # match first and the enum field is only a fallback for genuine
  # nicknames where no exact match exists.
  class Extractor
    include CollegeMatching

    POSITIONS = %w[QB RB WR TE OL DL LB DB K/P].freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an expert at reading college football video game conference NIL spend tables and transcribing
      the exact values shown. Only report a value if you can actually see it — never guess.
    PROMPT

    def call(images)
      return { rows: [], colleges: colleges_json } if images.blank?

      raw = chat.with_schema(schema).ask(prompt, with: images).content
      rows = Array(raw["teams"]).select { |row| row.is_a?(Hash) }.map { |row| build_row(row) }

      { rows: rows, colleges: colleges_json }
    end

    private

    def chat
      RubyLLM.chat.with_instructions(SYSTEM_PROMPT)
    end

    def schema
      names = college_names
      RubyLLM::Schema.create do
        array :teams, description: "One entry per row in the table." do
          object do
            string :college_raw_name, description: "The TEAM column, exactly as shown"
            string :college_name, enum: names,
                   description: "The database college that college_raw_name refers to — use your knowledge of team " \
                                "nicknames/abbreviations. Only use '#{UNMATCHED}' if none of the options are a plausible match."
            integer :nil_total, description: "The NIL column — this team's total"
            integer :qb, description: "The QB column"
            integer :rb, description: "The RB column"
            integer :wr, description: "The WR column"
            integer :te, description: "The TE column"
            integer :ol, description: "The OL column"
            integer :dl, description: "The DL column"
            integer :lb, description: "The LB column"
            integer :db, description: "The DB column"
            integer :kp, description: "The K/P column"
          end
        end
      end
    end

    def prompt
      "This is a conference NIL spend table, split across multiple images if needed. Read every row, top to " \
        "bottom, across all images — the team's NIL total and its breakdown by position group."
    end

    def build_row(row)
      {
        college_raw_name: row["college_raw_name"],
        college_id: resolve_college(row["college_raw_name"], row["college_name"])&.id,
        nil_total: row["nil_total"],
        # An array of {position, amount} rather than a {"QB" => amount} hash — the frontend's camelCase/
        # snake_case key conversion would otherwise mangle literal position labels like "QB" or "K/P" as if
        # they were JS identifiers (e.g. "QB" -> "_q_b"). Position names here are values, not object keys,
        # so they pass through untouched.
        by_position: POSITIONS.map { |position| { position: position, amount: row[position_key(position)] } }
      }
    end

    def position_key(position)
      position == "K/P" ? "kp" : position.downcase
    end
  end
end
