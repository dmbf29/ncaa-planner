module AllAmericans
  # Extracts player rows from one All-American list's screenshot(s) — all
  # images given here are already known (via ImageClassifier) to belong to
  # the same list, so this only has to read the table itself.
  #
  # First/last name are extracted as separate fields rather than one "full
  # name" field split in Ruby, since real names include suffixes and
  # hyphens (e.g. "Mark Fletcher Jr.", "Ryan Coleman-Williams") that a
  # naive last-space split gets wrong — the model already knows the
  # convention.
  #
  # Team names get the same enum-constrained matching ScheduleStats uses
  # for opponent colleges, for the same reason: this screen's names don't
  # always match colleges.name verbatim (e.g. "Ole Miss" is exact, but
  # others aren't). As discovered there, the enum field itself is unsafe to
  # trust directly — it consistently truncates a correct longer answer down
  # to a shorter college name that's also a valid enum value and an exact
  # prefix of the right one ("Arkansas State" -> "Arkansas", "Ohio State"
  # -> "Ohio") — so college_raw_name (plain text, unaffected) is checked
  # for an exact match first and the enum field is only a fallback for
  # genuine nicknames where no exact match exists.
  class RosterExtractor
    include CollegeMatching

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an expert at reading college football video game All-American team screenshots and
      transcribing the exact values shown. Only report a value if you can actually see it — never guess.
    PROMPT

    def call(images)
      return [] if images.blank?

      raw = chat.with_schema(schema).ask(prompt, with: images).content
      Array(raw["players"]).select { |row| row.is_a?(Hash) }.map { |row| build_row(row) }
    end

    private

    def chat
      RubyLLM.chat.with_instructions(SYSTEM_PROMPT)
    end

    def schema
      names = college_names
      RubyLLM::Schema.create do
        array :players, description: "One entry per row in the table, in the order shown." do
          object do
            string :first_name, description: "Player's first name"
            string :last_name, description: "Player's last name (include suffixes like Jr./III here, not in first_name)"
            string :position, description: "The POS column, e.g. 'QB', 'LT'"
            string :college_raw_name, description: "The TEAM column, exactly as shown (ignore any leading rank number)"
            string :college_name, enum: names,
                   description: "The database college that college_raw_name refers to — use your knowledge of team " \
                                "nicknames/abbreviations. Only use '#{UNMATCHED}' if none of the options are a plausible match."
            string :class_year, description: "The YEAR column exactly as shown, e.g. 'JR', 'SO (RS)'"
          end
        end
      end
    end

    def prompt
      "This is one All-American team list, split across multiple images if needed. Read every row, top to bottom, across all images."
    end

    def build_row(row)
      {
        first_name: row["first_name"],
        last_name: row["last_name"],
        position: row["position"],
        college_raw_name: row["college_raw_name"],
        college_id: resolve_college(row["college_raw_name"], row["college_name"])&.id,
        class_year: normalize_class_year(row["class_year"])
      }
    end

    def normalize_class_year(value)
      return value if value.blank?

      # DB convention has no space before the redshirt suffix, e.g. "SO(RS)" not "SO (RS)".
      value.gsub(/\s+\(/, "(")
    end
  end
end
