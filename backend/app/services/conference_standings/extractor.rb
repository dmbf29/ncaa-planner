module ConferenceStandings
  # Extracts a conference standings table (conference W-L, conference PF/PA,
  # overall W-L, overall PF/PA, home W-L) from however many screenshots it
  # takes to show the whole conference. There's no coached-team filtering —
  # every row shown gets extracted, same as NilSpend::Extractor, since
  # Colleges are league context even when not coached.
  #
  # This is a snapshot of "current" standings (no week association) — a
  # fresh upload is meant to replace the previous numbers outright, per
  # ConferenceStandings::CommitService.
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
    UNMATCHED = "Unmatched".freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an expert at reading college football video game conference standings tables and transcribing
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
            integer :conference_wins, description: "First number in the CONF column (conference W-L)"
            integer :conference_losses, description: "Second number in the CONF column (conference W-L)"
            integer :conference_points_for, description: "The CPF column — conference points for"
            integer :conference_points_against, description: "The CPA column — conference points against"
            integer :wins, description: "First number in the W-L column (overall record)"
            integer :losses, description: "Second number in the W-L column (overall record)"
            integer :points_for, description: "The PF column — overall points for"
            integer :points_against, description: "The PA column — overall points against"
            integer :home_wins, description: "First number in the HOME column"
            integer :home_losses, description: "Second number in the HOME column"
          end
        end
      end
    end

    def prompt
      "This is a college football conference standings table, split across multiple images if needed. Read " \
        "every row, top to bottom, across all images."
    end

    def build_row(row)
      {
        college_raw_name: row["college_raw_name"],
        college_id: resolve_college(row["college_raw_name"], row["college_name"])&.id,
        conference_wins: row["conference_wins"],
        conference_losses: row["conference_losses"],
        conference_points_for: row["conference_points_for"],
        conference_points_against: row["conference_points_against"],
        wins: row["wins"],
        losses: row["losses"],
        points_for: row["points_for"],
        points_against: row["points_against"],
        home_wins: row["home_wins"],
        home_losses: row["home_losses"]
      }
    end

    # Prefers an exact match on the plain-text raw name over the
    # enum-constrained field — see the class comment for why.
    def resolve_college(raw_name, matched_name)
      colleges_by_downcased_name[raw_name.to_s.strip.downcase] ||
        (matched_name.present? && matched_name != UNMATCHED ? colleges_by_name[matched_name] : nil)
    end

    def colleges
      @colleges ||= College.order(:name).to_a
    end

    def colleges_by_name
      @colleges_by_name ||= colleges.index_by(&:name)
    end

    def colleges_by_downcased_name
      @colleges_by_downcased_name ||= colleges.index_by { |college| college.name.downcase }
    end

    def college_names
      @college_names ||= colleges.map(&:name) + [ UNMATCHED ]
    end

    def colleges_json
      colleges.map { |college| { id: college.id, name: college.name } }
    end
  end
end
