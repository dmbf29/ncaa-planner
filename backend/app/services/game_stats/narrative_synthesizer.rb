module GameStats
  # Text-only pass over already-extracted stats to synthesize the game's
  # narrative summary and offense/defense player-of-the-game picks. Runs
  # after VisionExtractor, not against the images themselves.
  class NarrativeSynthesizer
    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are a college football beat writer producing short, punchy game-recap notes for a podcast
      production team, based on a completed box score and player stat lines.
    PROMPT

    def initialize(home_college:, away_college:)
      @home_college = home_college
      @away_college = away_college
    end

    def call(college_stats:, player_stats:)
      raw = chat.ask(prompt(college_stats, player_stats)).content
      valid_ids = player_stats.filter_map { |row| row[:student_season_id] }.to_set

      {
        narrative_summary: raw["narrative_summary"],
        offense_player_of_game_id: valid_id(raw["offense_player_of_game_student_season_id"], valid_ids),
        offense_player_stat_line: raw["offense_player_stat_line"],
        defense_player_of_game_id: valid_id(raw["defense_player_of_game_student_season_id"], valid_ids),
        defense_player_stat_line: raw["defense_player_stat_line"]
      }
    end

    private

    def valid_id(id, valid_ids)
      id if id && valid_ids.include?(id)
    end

    def chat
      RubyLLM.chat.with_instructions(SYSTEM_PROMPT).with_schema(schema)
    end

    def schema
      RubyLLM::Schema.create do
        string :narrative_summary,
               description: "2-4 sentence recap of how the game went — key runs, turning points, final margin."
        integer :offense_player_of_game_student_season_id, required: false,
                description: "student_season_id of the best offensive performer, from either team. " \
                             "Only set this if that player has a student_season_id in the data given below."
        string :offense_player_stat_line, required: false,
               description: "Short human-readable stat line, e.g. '18 carries, 142 yards, 2 TD'"
        integer :defense_player_of_game_student_season_id, required: false,
                description: "student_season_id of the best defensive performer, from either team. " \
                             "Only set this if that player has a student_season_id in the data given below."
        string :defense_player_stat_line, required: false,
               description: "Short human-readable stat line, e.g. '9 tackles, 1 INT'"
      end
    end

    def prompt(college_stats, player_stats)
      <<~PROMPT
        #{@home_college.name} (home) vs #{@away_college.name} (away)

        Team totals:
        #{college_stats.map { |row| team_line(row) }.join("\n")}

        Player stat lines:
        #{player_stats.map { |row| player_line(row) }.join("\n")}

        Pick the offense and defense players of the game from either team. If the standout player has no
        student_season_id listed above, you may still mention them by name in the narrative summary, but
        leave the corresponding *_student_season_id field unset rather than guessing an id.
      PROMPT
    end

    def team_line(row)
      f = row[:fields]
      "#{row[:team]}: #{f[:final_score]} points, #{f[:total_yards]} total yards, #{f[:turnovers]} turnovers"
    end

    def player_line(row)
      stats = row[:fields].map { |key, value| "#{key}=#{value}" }.join(", ")
      id_note = row[:student_season_id] ? " [student_season_id=#{row[:student_season_id]}]" : " [no student_season_id]"
      "#{row[:display_name]} (#{row[:team]}, #{row[:category]})#{id_note}: #{stats}"
    end
  end
end
