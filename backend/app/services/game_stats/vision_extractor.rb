module GameStats
  # Reads box score / player stat screenshots for a single game and returns
  # raw structured data via RubyLLM's vision + JSON-schema support. Does not
  # touch the database — callers decide what to do with the result.
  class VisionExtractor
    COLLEGE_FIELDS = %i[
      first_downs total_offense total_plays yards_per_play
      rushes rushing_yards rushing_tds yards_per_rush
      passing_completions passing_attempts passing_tds yards_per_pass passing_yards
      third_down_conversions third_down_attempts
      fourth_down_conversions fourth_down_attempts
      two_point_conversions two_point_attempts
      red_zone_tds red_zone_field_goals red_zone_success_percentage
      turnovers fumbles_lost interceptions_thrown
      punt_return_yards kick_return_yards total_yards
      punts penalties penalty_yards
      points_in_quarter_1 points_in_quarter_2 points_in_quarter_3 points_in_quarter_4
      final_score
    ].freeze

    PLAYER_FIELDS = %i[
      passing_rating passing_yards passing_tds passing_interceptions passing_longest
      passing_sacks_taken passing_completions passing_attempts passing_avg
      rushing_carries rushing_yards rushing_avg rushing_tds rushing_fumbles rushing_yac rushing_longest
      receiving_receptions receiving_yards receiving_avg receiving_tds receiving_rac receiving_longest receiving_drop
      defense_solo_tackles defense_assist_tackles defense_tackles defense_tfl defense_sacks
      defense_interceptions defense_interceptions_longest
    ].freeze

    CATEGORIES = %w[passing rushing receiving defense].freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an expert at reading college football video game box score and player stat screenshots and
      transcribing the exact numbers shown. Only report a value if you can actually see it in one of the
      provided images — never guess, estimate, or infer a number that isn't visibly printed on screen. Leave
      a field unset if it is not visible in any image.
    PROMPT

    def initialize(home_college:, away_college:, home_roster:, away_roster:)
      @home_college = home_college
      @away_college = away_college
      @home_roster = home_roster
      @away_roster = away_roster
    end

    def call(image_blobs)
      raw = chat.ask(prompt, with: image_blobs).content

      {
        college_stats: Array(raw["college_stats"]).map { |row| build_college_entry(row) },
        player_stats: Array(raw["player_stats"]).map { |row| build_player_entry(row) }
      }
    end

    private

    def chat
      RubyLLM.chat.with_instructions(SYSTEM_PROMPT).with_schema(schema)
    end

    def team_names
      [ @home_college.name, @away_college.name ]
    end

    def schema
      names = team_names

      RubyLLM::Schema.create do
        array :college_stats,
              description: "One entry per team from the box score screenshot(s) — exactly two entries expected." do
          object do
            string :team, enum: names
            integer :first_downs, required: false
            integer :total_offense, required: false
            integer :total_plays, required: false
            number :yards_per_play, required: false
            integer :rushes, required: false, description: "First number in 'Rushes-Yards-TDs', e.g. 31 in '31-103-0'"
            integer :rushing_yards, required: false, description: "Second number in 'Rushes-Yards-TDs'"
            integer :rushing_tds, required: false, description: "Third number in 'Rushes-Yards-TDs'"
            number :yards_per_rush, required: false
            integer :passing_completions, required: false, description: "First number in 'Comp-Att-TDs'"
            integer :passing_attempts, required: false, description: "Second number in 'Comp-Att-TDs'"
            integer :passing_tds, required: false, description: "Third number in 'Comp-Att-TDs' (not the Passing Yards row)"
            number :yards_per_pass, required: false
            integer :passing_yards, required: false, description: "The separate 'Passing Yards' row"
            integer :third_down_conversions, required: false, description: "First number in '3rd Down Conv.'"
            integer :third_down_attempts, required: false, description: "Second number in '3rd Down Conv.'"
            integer :fourth_down_conversions, required: false, description: "First number in '4th Down Conv.'"
            integer :fourth_down_attempts, required: false, description: "Second number in '4th Down Conv.'"
            integer :two_point_conversions, required: false,
                    description: "First number in '2-Point Conv.' (successful conversions, not attempts)"
            integer :two_point_attempts, required: false, description: "Second number in '2-Point Conv.'"
            integer :red_zone_tds, required: false, description: "First number in 'Red Zone TD-FG-%'"
            integer :red_zone_field_goals, required: false, description: "Second number in 'Red Zone TD-FG-%'"
            number :red_zone_success_percentage, required: false, description: "Third value in 'Red Zone TD-FG-%'"
            integer :turnovers, required: false
            integer :fumbles_lost, required: false, description: "'Fumble Lost' row"
            integer :interceptions_thrown, required: false, description: "'Interceptions' row"
            integer :punt_return_yards, required: false, description: "'PR Yards' row"
            integer :kick_return_yards, required: false, description: "'KR Yards' row"
            integer :total_yards, required: false
            integer :punts, required: false, description: "First number in 'Punts - Avg'"
            integer :penalties, required: false, description: "First number in 'Penalties - Yards'"
            integer :penalty_yards, required: false, description: "Second number in 'Penalties - Yards'"
            integer :time_of_possession_minutes, required: false, description: "Minutes portion of the T.O.P. clock"
            integer :time_of_possession_seconds, required: false, description: "Seconds portion of the T.O.P. clock"
            integer :points_in_quarter_1, required: false
            integer :points_in_quarter_2, required: false
            integer :points_in_quarter_3, required: false
            integer :points_in_quarter_4, required: false
            integer :final_score, required: false, description: "The 'Score' / 'Final' total"
          end
        end

        array :player_stats,
              description: "One entry per player per stat-category screenshot (passing/rushing/receiving/defense). " \
                           "A player shown in more than one category screenshot (e.g. a rushing QB) gets a " \
                           "separate entry per category, not a merged one." do
          object do
            string :player_display_name, description: "Exactly as shown on screen, e.g. 'H.Crandall'"
            string :team, enum: names
            string :category, enum: CATEGORIES
            integer :student_season_id, required: false,
                    description: "id of the matching player from the roster list given in the prompt, " \
                                 "only if confidently matched. Leave unset otherwise."
            number :passing_rating, required: false
            integer :passing_yards, required: false
            integer :passing_tds, required: false
            integer :passing_interceptions, required: false
            integer :passing_longest, required: false
            integer :passing_sacks_taken, required: false
            integer :passing_completions, required: false
            integer :passing_attempts, required: false
            number :passing_avg, required: false, description: "Completion percentage, shown as COMP%"
            integer :rushing_carries, required: false
            integer :rushing_yards, required: false
            number :rushing_avg, required: false
            integer :rushing_tds, required: false
            integer :rushing_fumbles, required: false
            integer :rushing_yac, required: false
            integer :rushing_longest, required: false
            integer :receiving_receptions, required: false
            integer :receiving_yards, required: false
            number :receiving_avg, required: false
            integer :receiving_tds, required: false
            integer :receiving_rac, required: false
            integer :receiving_longest, required: false
            integer :receiving_drop, required: false
            integer :defense_solo_tackles, required: false
            integer :defense_assist_tackles, required: false
            integer :defense_tackles, required: false
            integer :defense_tfl, required: false
            number :defense_sacks, required: false
            integer :defense_interceptions, required: false
            integer :defense_interceptions_longest, required: false
          end
        end
      end
    end

    def prompt
      <<~PROMPT
        These screenshots are all from ONE game between #{@home_college.name} (home) and #{@away_college.name} (away).
        You may see 1-2 box score screenshots (sometimes the same table scrolled to show different rows, covering
        both teams side by side) and up to 8 individual player-stat screenshots (up to 4 per team: passing,
        rushing, receiving, defense). Not every screenshot type is guaranteed to be present — only report what you
        can actually see.

        Team names may appear on screen slightly differently than listed here (e.g. "Jacksonville State" vs
        "Jax State") — always map them back to exactly "#{@home_college.name}" or "#{@away_college.name}" in
        your response.

        #{roster_section(@home_college, @home_roster)}

        #{roster_section(@away_college, @away_roster)}
      PROMPT
    end

    def roster_section(college, roster)
      return "#{college.name} roster: none available — report player_display_name only, leave student_season_id unset." if roster.empty?

      lines = roster.map { |player| "- id #{player[:id]}: #{player[:name]} (#{player[:position]})" }
      "#{college.name} roster:\n#{lines.join("\n")}"
    end

    def build_college_entry(row)
      fields = row.slice(*COLLEGE_FIELDS.map(&:to_s)).transform_keys(&:to_sym)
      minutes = row["time_of_possession_minutes"]
      seconds = row["time_of_possession_seconds"]
      fields[:time_of_possession] = (minutes.to_i * 60) + seconds.to_i if minutes || seconds

      { team: row["team"], fields: fields.compact }
    end

    def build_player_entry(row)
      {
        team: row["team"],
        category: row["category"],
        display_name: row["player_display_name"],
        student_season_id: row["student_season_id"],
        fields: row.slice(*PLAYER_FIELDS.map(&:to_s)).transform_keys(&:to_sym).compact
      }
    end
  end
end
