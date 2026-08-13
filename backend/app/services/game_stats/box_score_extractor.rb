module GameStats
  # Extracts CollegeGameStat fields for both teams from the box score
  # screenshot(s). Split into several small calls (~9-10 optional fields
  # each) since empirically Anthropic's structured-output grammar compiler
  # starts rejecting schemas as "too complex" well before its documented
  # 24-optional-parameter cap — around 10-14 fields in practice.
  class BoxScoreExtractor
    FLOAT_FIELDS = %i[yards_per_play yards_per_rush yards_per_pass red_zone_success_percentage].freeze

    FIELD_DESCRIPTIONS = {
      rushes: "First number in 'Rushes-Yards-TDs', e.g. 31 in '31-103-0'",
      rushing_yards: "Second number in 'Rushes-Yards-TDs'",
      rushing_tds: "Third number in 'Rushes-Yards-TDs'",
      passing_completions: "First number in 'Comp-Att-TDs'",
      passing_attempts: "Second number in 'Comp-Att-TDs'",
      passing_tds: "Third number in 'Comp-Att-TDs' (not the Passing Yards row)",
      passing_yards: "The separate 'Passing Yards' row",
      third_down_conversions: "First number in '3rd Down Conv.'",
      third_down_attempts: "Second number in '3rd Down Conv.'",
      fourth_down_conversions: "First number in '4th Down Conv.'",
      fourth_down_attempts: "Second number in '4th Down Conv.'",
      two_point_conversions: "First number in '2-Point Conv.' (successful conversions, not attempts)",
      two_point_attempts: "Second number in '2-Point Conv.'",
      red_zone_tds: "First number in 'Red Zone TD-FG-%'",
      red_zone_field_goals: "Second number in 'Red Zone TD-FG-%'",
      red_zone_success_percentage: "Third value in 'Red Zone TD-FG-%'",
      fumbles_lost: "'Fumble Lost' row",
      interceptions_thrown: "'Interceptions' row",
      punt_return_yards: "'PR Yards' row",
      kick_return_yards: "'KR Yards' row",
      punts: "First number in 'Punts - Avg'",
      penalties: "First number in 'Penalties - Yards'",
      penalty_yards: "Second number in 'Penalties - Yards'",
      final_score: "The 'Score' / 'Final' total",
      points_in_overtime: "Points scored in overtime periods combined — only present if the game went to OT"
    }.freeze

    GROUPS = [
      %i[first_downs total_offense total_plays yards_per_play total_yards
         points_in_quarter_1 points_in_quarter_2 points_in_quarter_3 points_in_quarter_4
         points_in_overtime final_score],
      %i[rushes rushing_yards rushing_tds yards_per_rush
         passing_completions passing_attempts passing_tds yards_per_pass passing_yards],
      %i[third_down_conversions third_down_attempts fourth_down_conversions fourth_down_attempts
         two_point_conversions two_point_attempts
         red_zone_tds red_zone_field_goals red_zone_success_percentage],
      %i[turnovers fumbles_lost interceptions_thrown
         punt_return_yards kick_return_yards punts penalties penalty_yards]
    ].freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an expert at reading college football video game box score screenshots and transcribing the
      exact numbers shown for BOTH teams. Only report a value if you can actually see it — never guess.
      Leave a field unset if it is not visible in any image.
    PROMPT

    def initialize(home_college:, away_college:)
      @home_college = home_college
      @away_college = away_college
    end

    def call(image_blobs)
      return [] if image_blobs.blank?

      # Time of possession rides along with the last group rather than getting its own tiny call.
      results = GROUPS.each_with_index.map do |fields, index|
        run_group(image_blobs, fields, include_time: index == GROUPS.size - 1)
      end

      merged = team_names.index_with { |_name| {} }
      results.each { |by_team| merged.each_key { |name| merged[name].merge!(by_team[name] || {}) } }

      merged.map { |name, row| build_entry(name, row) }
    end

    private

    def team_names
      [ @home_college.name, @away_college.name ]
    end

    # Retry once if a call doesn't come back with both teams represented —
    # cheap insurance against the same kind of occasional empty/partial
    # response PlayerCategoryExtractor guards against.
    def run_group(image_blobs, fields, include_time:)
      by_team = fetch_group(image_blobs, fields, include_time: include_time)
      by_team = fetch_group(image_blobs, fields, include_time: include_time) unless (team_names - by_team.keys).empty?
      by_team
    end

    def fetch_group(image_blobs, fields, include_time:)
      chat = RubyLLM.chat.with_instructions(SYSTEM_PROMPT).with_schema(group_schema(fields, include_time: include_time))
      raw = chat.ask(prompt, with: image_blobs).content
      Array(raw["college_stats"]).select { |row| row.is_a?(Hash) }.index_by { |row| row["team"] }
    end

    def group_schema(fields, include_time:)
      names = team_names
      float_fields = FLOAT_FIELDS
      descriptions = FIELD_DESCRIPTIONS

      RubyLLM::Schema.create do
        array :college_stats, description: "One entry per team — exactly two entries expected." do
          object do
            string :team, enum: names
            fields.each do |field|
              if float_fields.include?(field)
                number field, required: false, description: descriptions[field]
              else
                integer field, required: false, description: descriptions[field]
              end
            end
            if include_time
              integer :time_of_possession_minutes, required: false, description: "Minutes portion of the T.O.P. clock"
              integer :time_of_possession_seconds, required: false, description: "Seconds portion of the T.O.P. clock"
            end
          end
        end
      end
    end

    def prompt
      "These screenshots are box score(s) for #{@home_college.name} (home) vs #{@away_college.name} (away). " \
        "Team names may appear differently on screen (e.g. a full name instead of an abbreviation) — always " \
        "map them back to exactly one of those two names in your response."
    end

    def build_entry(team, row)
      fields = row.slice(*StatFields::COLLEGE_FIELDS.map(&:to_s)).transform_keys(&:to_sym)
      minutes = row["time_of_possession_minutes"]
      seconds = row["time_of_possession_seconds"]
      fields[:time_of_possession] = (minutes.to_i * 60) + seconds.to_i if minutes || seconds

      { team: team, fields: fields.compact }
    end
  end
end
