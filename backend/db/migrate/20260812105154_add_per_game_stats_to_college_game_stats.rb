class AddPerGameStatsToCollegeGameStats < ActiveRecord::Migration[8.0]
  def change
    add_column :college_game_stats, :points_per_game, :float
    add_column :college_game_stats, :yards_per_game, :float
    add_column :college_game_stats, :passing_yards_per_game, :float
    add_column :college_game_stats, :rushing_yards_per_game, :float
  end
end
