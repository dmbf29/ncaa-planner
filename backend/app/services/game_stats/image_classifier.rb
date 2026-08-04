module GameStats
  # Cheap pass to figure out which stat category (passing/rushing/receiving/
  # defense) a team's screenshot shows, so PlayerCategoryExtractor only
  # looks at the relevant image(s). Team is already known from which upload
  # bucket the image came in, so this only has to guess category — a
  # smaller, safer classification task than guessing team too.
  class ImageClassifier
    TYPES = (StatFields::CATEGORIES + %w[unknown]).freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You classify college football video game player-stat screenshots. For each image (by its 0-based
      index in the order given), say which stat category it shows: passing, rushing, receiving, or defense.
      If an image doesn't match any of these, use "unknown".
    PROMPT

    def initialize(team_name:)
      @team_name = team_name
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
      RubyLLM::Schema.create do
        array :screenshots do
          object do
            integer :index, description: "0-based position of this image in the order it was given"
            string :type, enum: TYPES
          end
        end
      end
    end

    def prompt(count)
      "There are #{count} player-stat screenshots for #{@team_name}, indexed 0 to #{count - 1} in the order " \
        "given. Classify each one."
    end

    def build_entry(row)
      index = row["index"]
      return nil unless index.is_a?(Integer)

      { index: index, type: row["type"] }
    end
  end
end
