module AllAmericans
  # Classifies each uploaded screenshot by which All-American list it shows
  # (National vs. a specific conference, 1st/2nd team, preseason or not) so
  # RosterExtractor can group same-list screenshots together before reading
  # player rows out of them. A user might upload up to 12 screenshots
  # spanning 4 different lists in one batch (3 shots each for National 1st,
  # National 2nd, Conference 1st, Conference 2nd) — nothing on an individual
  # player row says which list it came from, only the screenshot's header
  # does, so this has to run before row extraction rather than alongside it.
  #
  # Empirically, Anthropic's structured-output API rejects `minimum`/
  # `maximum` on integer schema fields outright ("properties maximum,
  # minimum are not supported") — a different failure mode from the
  # optional-field-count limit documented on PlayerCategoryExtractor, but
  # the same lesson: constrain via the field description text, not
  # JSON-schema-level numeric bounds.
  class ImageClassifier
    SCOPE_NATIONAL = "National".freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You classify college football video game All-American team screenshots. Each one has a header
      showing which list it is: the top-left says "NATIONAL" or a conference name, and the top-right says
      "[PRESEASON] 1ST TEAM" or "[PRESEASON] 2ND TEAM".
    PROMPT

    def call(images)
      return [] if images.blank?

      raw = chat.with_schema(schema).ask(prompt(images.size), with: images).content
      Array(raw["screenshots"]).filter_map { |row| build_entry(row) }
    end

    private

    def chat
      RubyLLM.chat.with_instructions(SYSTEM_PROMPT)
    end

    def schema
      scopes = scope_options
      RubyLLM::Schema.create do
        array :screenshots do
          object do
            integer :index, description: "0-based position of this image in the order it was given"
            string :scope, enum: scopes, description: "Top-left header text — 'National' or the conference name"
            integer :tier, description: "1 for '1ST TEAM', 2 for '2ND TEAM' — no other values are valid"
            boolean :preseason, description: "True if the top-right header includes the word 'PRESEASON'"
          end
        end
      end
    end

    def prompt(count)
      "There are #{count} All-American list screenshots, indexed 0 to #{count - 1} in the order given. Classify each one."
    end

    def build_entry(row)
      index = row["index"]
      tier = row["tier"]
      return nil unless index.is_a?(Integer) && [ 1, 2 ].include?(tier)

      { index: index, scope: row["scope"], tier: tier, preseason: row["preseason"] }
    end

    def scope_options
      College.distinct.where.not(conference: [ nil, "FCS" ]).order(:conference).pluck(:conference) + [ SCOPE_NATIONAL ]
    end
  end
end
