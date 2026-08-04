module GameStats
  # Cheap first pass: figures out which uploaded screenshot is which (box
  # score vs. a specific team's passing/rushing/receiving/defense table) so
  # later extraction calls only need the images relevant to them. Splitting
  # extraction this way is also what keeps each call's schema small enough
  # to stay under Anthropic's structured-output limit on optional fields.
  class ImageClassifier
    TYPES = (%w[box_score] + StatFields::CATEGORIES + %w[unknown]).freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You classify college football video game screenshots. For each image (by its 0-based index in the
      order given), say whether it's a combined box score (both teams' team stats shown side by side), or a
      single team's player stat table for one specific category (passing, rushing, receiving, or defense).
      If an image doesn't match any of these, use "unknown".
    PROMPT

    def initialize(home_college:, away_college:)
      @home_college = home_college
      @away_college = away_college
    end

    def call(image_blobs)
      return [] if image_blobs.blank?

      raw = chat.ask(prompt(image_blobs.size), with: image_blobs).content
      Array(raw["screenshots"]).filter_map { |row| build_entry(row) }
    end

    private

    def chat
      RubyLLM.chat.with_instructions(SYSTEM_PROMPT).with_schema(schema)
    end

    def schema
      names = [ @home_college.name, @away_college.name ]

      RubyLLM::Schema.create do
        array :screenshots do
          object do
            integer :index, description: "0-based position of this image in the order it was given"
            string :type, enum: TYPES
            string :team, required: false, enum: names,
                   description: "Which team this screenshot is for. Only set for passing/rushing/receiving/defense " \
                                "screenshots, leave unset for box_score or unknown."
          end
        end
      end
    end

    def prompt(count)
      "There are #{count} images, indexed 0 to #{count - 1} in the order given. Classify each one. " \
        "Teams are \"#{@home_college.name}\" (home) and \"#{@away_college.name}\" (away)."
    end

    def build_entry(row)
      index = row["index"]
      return nil unless index.is_a?(Integer)

      { index: index, type: row["type"], team: row["team"] }
    end
  end
end
