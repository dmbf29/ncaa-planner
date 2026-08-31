class CreateCollegeGameStats < ActiveRecord::Migration[8.0]
  def change
    create_table :college_game_stats do |t|
      t.references :game, null: false, foreign_key: true
      t.references :college, null: false, foreign_key: true
      t.integer :first_downs
      t.integer :total_offense
      t.integer :total_plays
      t.float :yards_per_play
      t.integer :rushes
      t.integer :rushing_yards
      t.integer :rushing_tds
      t.float :yards_per_rush
      t.integer :passing_completions
      t.integer :passing_attempts
      t.integer :passing_yards
      t.integer :passing_tds
      t.float :yards_per_pass
      t.integer :third_down_conversions
      t.integer :third_down_attempts
      t.integer :fourth_down_conversions
      t.integer :fourth_down_attempts
      t.integer :two_point_attempts
      t.integer :two_point_conversions
      t.integer :red_zone_tds
      t.integer :red_zone_field_goals
      t.float :red_zone_success_percentage
      t.integer :turnovers
      t.integer :fumbles_lost
      t.integer :interceptions_thrown
      t.integer :punt_return_yards
      t.integer :kick_return_yards
      t.integer :total_yards
      t.integer :punts
      t.integer :penalties
      t.integer :penalty_yards
      t.integer :time_of_possession
      t.integer :points_in_quarter_1
      t.integer :points_in_quarter_2
      t.integer :points_in_quarter_3
      t.integer :points_in_quarter_4
      t.integer :final_score

      t.index [:game_id, :college_id], unique: true, name: "index_college_game_stats_on_game_and_college"

      t.timestamps
    end
  end
end
