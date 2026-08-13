module GameStats
  # DB column lists shared across the extraction services and CommitService,
  # so mass-assignment stays whitelisted to real CollegeGameStat /
  # StudentGameStat columns regardless of which extractor produced the row.
  module StatFields
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
      punts penalties penalty_yards time_of_possession
      points_in_quarter_1 points_in_quarter_2 points_in_quarter_3 points_in_quarter_4
      points_in_overtime final_score
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
  end
end
