module HeismanCandidates
  # Extracts one week's Heisman Watch List (always exactly 4 rows) from
  # however many screenshots it takes. Unlike AllAmericans::Extractor,
  # there's only ever one list per upload — nothing on screen distinguishes
  # "which list" the way National/Conference/1st/2nd team headers do — so
  # no image-classification pass is needed first, just a single row read.
  #
  # Team names get the same enum-constrained matching ScheduleStats/
  # AllAmericans use, since this screen's names don't always match
  # colleges.name verbatim. As discovered there, the enum field itself is
  # unsafe to trust directly — it consistently truncates a correct longer
  # answer down to a shorter college name that's also a valid enum value
  # and an exact prefix of the right one ("Arkansas State" -> "Arkansas",
  # "Ohio State" -> "Ohio") — so college_raw_name (plain text, unaffected)
  # is checked for an exact match first and the enum field is only a
  # fallback for genuine nicknames where no exact match exists.
  #
  # Order isn't tracked at all — the set of candidates for a week is what
  # matters, not their standing relative to each other.
  class Extractor
    UNMATCHED = "Unmatched".freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an expert at reading college football video game Heisman Watch List screenshots and
      transcribing the exact values shown. Only report a value if you can actually see it — never guess.
    PROMPT

    def call(images)
      return { rows: [], colleges: colleges_json } if images.blank?

      raw = chat.with_schema(schema).ask(prompt, with: images).content
      rows = Array(raw["candidates"]).select { |row| row.is_a?(Hash) }.map { |row| build_row(row) }

      { rows: rows, colleges: colleges_json }
    end

    private

    def chat
      RubyLLM.chat.with_instructions(SYSTEM_PROMPT)
    end

    def schema
      names = college_names
      RubyLLM::Schema.create do
        array :candidates, description: "One entry per row in the table." do
          object do
            string :first_name, description: "Player's first name"
            string :last_name, description: "Player's last name (include suffixes like Jr./III here, not in first_name)"
            string :position, description: "The POS column, e.g. 'QB', 'WR'"
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
      "This is a Heisman Watch List, split across multiple images if needed. Read every row, across all " \
        "images. There should be exactly 4 candidates."
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

    # Prefers an exact match on the plain-text raw name over the
    # enum-constrained field — see the class comment for why.
    def resolve_college(raw_name, matched_name)
      colleges_by_downcased_name[raw_name.to_s.strip.downcase] ||
        (matched_name.present? && matched_name != UNMATCHED ? colleges_by_name[matched_name] : nil)
    end

    def normalize_class_year(value)
      return value if value.blank?

      # DB convention has no space before the redshirt suffix, e.g. "SO(RS)" not "SO (RS)".
      value.gsub(/\s+\(/, "(")
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
