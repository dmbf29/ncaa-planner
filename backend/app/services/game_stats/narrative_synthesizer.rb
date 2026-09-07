module GameStats
  # Text-only pass over already-extracted stats to synthesize the game's
  # narrative summary and offense/defense player-of-the-game picks. Runs
  # after BoxScoreExtractor / PlayerCategoryExtractor, not against the
  # images themselves.
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
               description: "2-4 sentence recap of how the game went — key runs, turning points, final margin. " \
                            "Ground turning-point claims in the quarter-by-quarter scoring, time of possession, " \
                            "third-down and red-zone numbers given below; don't invent plays that aren't in the data."
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
      progression = scoring_progression(college_stats)

      <<~PROMPT
        #{@home_college.name} (home) vs #{@away_college.name} (away)

        #{progression}
        Team totals:
        #{college_stats.map { |row| team_line(row) }.join("\n")}

        Player stat lines:
        #{player_stats.map { |row| player_line(row) }.join("\n")}

        Pick the offense and defense players of the game from either team. If the standout player has no
        student_season_id listed above, you may still mention them by name in the narrative summary, but
        leave the corresponding *_student_season_id field unset rather than guessing an id.
        Do not describe any quarter or half as "scoreless" or a team as "shut out" over a span unless the
        running score line above shows no change for that team across that exact span — check it, don't
        infer it from the final margin.
      PROMPT
    end

    # Per-quarter point totals are correct in the data but the model has
    # repeatedly failed to *sum* them correctly on its own (e.g. calling a
    # half "scoreless" when a team scored in Q1) — so we do the addition
    # ourselves and hand over an unambiguous running score instead of
    # trusting the model to add four numbers per team.
    def scoring_progression(college_stats)
      quarter_keys = [ :points_in_quarter_1, :points_in_quarter_2, :points_in_quarter_3, :points_in_quarter_4 ]
      teams = college_stats.filter_map do |row|
        f = row[:fields]
        next unless quarter_keys.any? { |key| present?(f[key]) }

        quarters = quarter_keys.map { |key| f[key].to_i }
        quarters << f[:points_in_overtime].to_i if present?(f[:points_in_overtime])
        { team: row[:team], quarters: quarters }
      end
      return "" if teams.size < 2

      labels = [ "after Q1", "after Q2 (halftime)", "after Q3", "after Q4" ]
      running = Hash.new(0)
      lines = (0...teams.map { |t| t[:quarters].size }.max).map do |i|
        scores = teams.map { |t| "#{t[:team]} #{running[t[:team]] += t[:quarters][i].to_i}" }.join(" - ")
        "#{labels[i] || "after OT"}: #{scores}"
      end

      "Running score by quarter:\n#{lines.join("\n")}\n"
    end

    # Emit as much of the team's box score as we actually have — the
    # narrative pass gets no images and no play-by-play, so this line is
    # the model's only source of substance. Quarter-by-quarter scoring in
    # particular is what lets it write an honest "turning point" / "pulled
    # away late" sentence instead of guessing from total yards. Blank
    # fields are dropped so a partial extraction doesn't emit "/ yds".
    def team_line(row)
      f = row[:fields]
      parts = []

      if present?(f[:final_score])
        quarters = [ :points_in_quarter_1, :points_in_quarter_2, :points_in_quarter_3, :points_in_quarter_4 ]
                     .map { |key| f[key] }
        quarters << f[:points_in_overtime] if present?(f[:points_in_overtime])
        by_quarter = " (by quarter: #{quarters.map { |q| q || 0 }.join('-')})" if quarters.any? { |q| present?(q) }
        parts << "final #{f[:final_score]}#{by_quarter}"
      end

      if present?(f[:total_yards])
        yardage = "#{f[:total_yards]} total yards"
        yardage << " on #{f[:total_plays]} plays (#{f[:yards_per_play]}/play)" if present?(f[:total_plays])
        parts << yardage
      end
      parts << "#{f[:first_downs]} first downs" if present?(f[:first_downs])

      if present?(f[:rushing_yards])
        parts << "rush #{f[:rushing_yards]} yds/#{f[:rushes]} car (#{f[:yards_per_rush]} avg), #{f[:rushing_tds].to_i} TD"
      end
      if present?(f[:passing_yards])
        parts << "pass #{f[:passing_completions]}/#{f[:passing_attempts]} for #{f[:passing_yards]} yds, #{f[:passing_tds].to_i} TD"
      end

      parts << "3rd down #{f[:third_down_conversions]}/#{f[:third_down_attempts]}" if present?(f[:third_down_attempts])
      parts << "4th down #{f[:fourth_down_conversions]}/#{f[:fourth_down_attempts]}" if present?(f[:fourth_down_attempts])
      if present?(f[:red_zone_tds]) || present?(f[:red_zone_field_goals])
        parts << "red zone #{f[:red_zone_tds].to_i} TD/#{f[:red_zone_field_goals].to_i} FG (#{f[:red_zone_success_percentage]}%)"
      end

      if present?(f[:turnovers])
        parts << "#{f[:turnovers]} turnovers (#{f[:fumbles_lost].to_i} fum lost, #{f[:interceptions_thrown].to_i} INT)"
      end
      parts << "TOP #{f[:time_of_possession]}s" if present?(f[:time_of_possession])
      parts << "#{f[:penalties]} pen for #{f[:penalty_yards]} yds" if present?(f[:penalties])

      "#{row[:team]} — #{parts.join('; ')}"
    end

    def present?(value)
      !value.nil? && value.to_s.strip != ""
    end

    def player_line(row)
      stats = row[:fields].map { |key, value| "#{key}=#{value}" }.join(", ")
      id_note = row[:student_season_id] ? " [student_season_id=#{row[:student_season_id]}]" : " [no student_season_id]"
      "#{row[:display_name]} (#{row[:team]}, #{row[:category]})#{id_note}: #{stats}"
    end
  end
end
