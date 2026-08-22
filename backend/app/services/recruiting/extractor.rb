module Recruiting
  # Extracts a national recruiting class rankings table (rank, total signed,
  # NIL total, star breakdown, points) from however many screenshots it
  # takes to cover the whole list. There's no coached-team filtering — every
  # row shown gets extracted, same as NilSpend/ConferenceStandings, since
  # Colleges are league context even when not coached.
  #
  # This is a snapshot of the recruiting class as it stands — a fresh
  # upload is meant to replace the previous numbers outright, per
  # Recruiting::CommitService.
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

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an expert at reading college football video game recruiting class rankings tables and
      transcribing the exact values shown. Only report a value if you can actually see it — never guess.
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
            integer :ranking, description: "The RANK column"
            integer :total_signed, description: "The TOTAL column — total recruits signed"
            integer :nil_spent, description: "The NIL column"
            integer :five_stars, description: "The 5-STAR column"
            integer :four_stars, description: "The 4-STAR column"
            integer :three_stars, description: "The 3-STAR column"
            integer :two_stars, description: "The 2-STAR column"
            integer :one_stars, description: "The 1-STAR column"
            number :points, description: "The PTS column"
          end
        end
      end
    end

    def prompt
      "This is a college football national recruiting class rankings table, split across multiple images if " \
        "needed. Read every row, top to bottom, across all images."
    end

    def build_row(row)
      {
        college_raw_name: row["college_raw_name"],
        college_id: resolve_college(row["college_raw_name"], row["college_name"])&.id,
        ranking: row["ranking"],
        total_signed: row["total_signed"],
        nil_spent: row["nil_spent"],
        five_stars: row["five_stars"],
        four_stars: row["four_stars"],
        three_stars: row["three_stars"],
        two_stars: row["two_stars"],
        one_stars: row["one_stars"],
        points: row["points"]
      }
    end
  end
end
