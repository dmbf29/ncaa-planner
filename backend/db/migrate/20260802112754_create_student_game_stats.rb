class CreateStudentGameStats < ActiveRecord::Migration[8.0]
  def change
    create_table :student_game_stats do |t|
      t.references :game, null: false, foreign_key: true
      t.references :student_season, null: false, foreign_key: true
      t.float :passing_rating
      t.integer :passing_yards
      t.integer :passing_tds
      t.integer :passing_interceptions
      t.integer :passing_longest
      t.integer :passing_sacks_taken
      t.integer :passing_completions
      t.integer :passing_attempts
      t.float :passing_avg
      t.integer :rushing_carries
      t.integer :rushing_yards
      t.float :rushing_avg
      t.integer :rushing_tds
      t.integer :rushing_fumbles
      t.integer :rushing_yac
      t.integer :rushing_longest
      t.integer :receiving_receptions
      t.integer :receiving_yards
      t.float :receiving_avg
      t.integer :receiving_tds
      t.integer :receiving_rac
      t.integer :receiving_longest
      t.integer :receiving_drop
      t.integer :defense_solo_tackles
      t.integer :defense_assist_tackles
      t.integer :defense_tackles
      t.integer :defense_tfl
      t.float :defense_sacks
      t.integer :defense_interceptions
      t.integer :defense_interceptions_longest

      t.index [:game_id, :student_season_id], unique: true, name: "index_student_game_stats_on_game_and_student_season"

      t.timestamps
    end
  end
end
