module GameStats
  # Extracts StudentGameStat fields for one team's stat category (passing/
  # rushing/receiving/defense) from that category's screenshot(s). The team
  # is known from the caller (images are uploaded per-team), so the model
  # only has to identify the player and category fields, not guess team.
  #
  # Each category is split into two small calls (4-5 optional fields each)
  # and merged by player identity — empirically, a single call asking for
  # ~9 optional fields on a variable-length array of players was
  # unreliable (it would randomly omit several fields even when they were
  # clearly visible), while the same fields split into ~5-field groups
  # came back complete and accurate every time. Fixed-length arrays (like
  # BoxScoreExtractor's always-2-teams array) didn't show this problem
  # even at ~10 fields, so the culprit seems to be the combination of an
  # uncertain array length with a large per-item optional field count, not
  # raw field count alone.
  class PlayerCategoryExtractor
    FIELD_SETS = {
      "passing" => %i[
        passing_completions passing_attempts passing_yards passing_tds passing_interceptions
        passing_rating passing_longest passing_sacks_taken passing_avg
      ],
      "rushing" => %i[rushing_carries rushing_yards rushing_avg rushing_tds rushing_fumbles rushing_yac rushing_longest],
      "receiving" => %i[receiving_receptions receiving_yards receiving_avg receiving_tds receiving_rac receiving_longest receiving_drop],
      "defense" => %i[
        defense_solo_tackles defense_assist_tackles defense_tackles defense_tfl
        defense_sacks defense_interceptions defense_interceptions_longest
      ]
    }.freeze

    FIELD_GROUPS = {
      "passing" => [
        %i[passing_completions passing_attempts passing_yards passing_tds passing_interceptions],
        %i[passing_rating passing_longest passing_sacks_taken passing_avg]
      ],
      "rushing" => [
        %i[rushing_carries rushing_yards rushing_tds rushing_avg],
        %i[rushing_fumbles rushing_yac rushing_longest]
      ],
      "receiving" => [
        %i[receiving_receptions receiving_yards receiving_tds receiving_avg],
        %i[receiving_rac receiving_longest receiving_drop]
      ],
      "defense" => [
        %i[defense_solo_tackles defense_assist_tackles defense_tackles defense_tfl],
        %i[defense_sacks defense_interceptions defense_interceptions_longest]
      ]
    }.freeze

    FLOAT_FIELDS = %i[passing_rating passing_avg rushing_avg receiving_avg defense_sacks].freeze

    FIELD_DESCRIPTIONS = {
      passing_avg: "Completion percentage, shown as COMP%"
    }.freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an expert at reading college football video game player stat screenshots and transcribing the
      exact numbers shown. Only report a value if you can actually see it — never guess. Leave a field
      unset if it is not visible.
    PROMPT

    def initialize(category:, college:, roster:)
      @category = category
      @college = college
      @roster = roster
    end

    def call(image_blobs)
      return [] if image_blobs.blank?

      groups = FIELD_GROUPS.fetch(@category)
      results = groups.map { |fields| run_group(image_blobs, fields) }

      merge(results).map { |row| build_entry(row) }
    end

    private

    # Empirically, a sub-call occasionally comes back with an empty players
    # array even when the screenshot clearly has players on it. A single
    # retry clears this up almost every time it happens.
    def run_group(image_blobs, fields)
      rows = fetch_group(image_blobs, fields)
      rows = fetch_group(image_blobs, fields) if rows.empty?
      rows
    end

    def fetch_group(image_blobs, fields)
      chat = RubyLLM.chat.with_instructions(SYSTEM_PROMPT).with_schema(group_schema(fields))
      raw = chat.ask(prompt, with: image_blobs).content
      # Defensive: an occasional malformed response includes a bare string
      # instead of a proper row object, so filter those out rather than crash.
      Array(raw["players"]).select { |row| row.is_a?(Hash) }
    end

    def group_schema(fields)
      float_fields = FLOAT_FIELDS
      descriptions = FIELD_DESCRIPTIONS

      RubyLLM::Schema.create do
        array :players, description: "One entry per player shown in this stat table." do
          object do
            string :player_display_name, description: "Exactly as shown on screen, e.g. 'H.Crandall'"
            integer :student_season_id, required: false,
                    description: "id of the matching player from the roster given in the prompt, " \
                                 "only if confidently matched. Leave unset otherwise."
            fields.each do |field|
              if float_fields.include?(field)
                number field, required: false, description: descriptions[field]
              else
                integer field, required: false, description: descriptions[field]
              end
            end
          end
        end
      end
    end

    def prompt
      <<~PROMPT
        This is the #{@category} stat table for #{@college.name}.

        Player names are shown as first-initial + last name (e.g. "H.Crandall"). Match each one against the
        roster below and, only if confident, set student_season_id to that player's id. If no roster is
        given, or you can't confidently match, leave student_season_id unset but still report
        player_display_name and their stats.

        #{roster_section}
      PROMPT
    end

    def roster_section
      return "Roster: none available — report player_display_name only, leave student_season_id unset." if @roster.empty?

      lines = @roster.map { |player| "- id #{player[:id]}: #{player[:name]} (#{player[:position]})" }
      "Roster:\n#{lines.join("\n")}"
    end

    # Merges rows from the group sub-calls by display name so a player who
    # appears in both calls ends up as one row with all fields.
    def merge(results)
      merged = {}
      order = []

      results.each do |rows|
        rows.each do |row|
          key = row["player_display_name"].to_s.strip.downcase
          unless merged.key?(key)
            merged[key] = { "player_display_name" => row["player_display_name"] }
            order << key
          end
          merged[key]["student_season_id"] ||= row["student_season_id"]
          merged[key].merge!(row.except("player_display_name", "student_season_id"))
        end
      end

      order.map { |key| merged[key] }
    end

    def build_entry(row)
      {
        team: @college.name,
        category: @category,
        display_name: row["player_display_name"],
        student_season_id: row["student_season_id"],
        fields: row.slice(*FIELD_SETS.fetch(@category).map(&:to_s)).transform_keys(&:to_sym).compact
      }
    end
  end
end
