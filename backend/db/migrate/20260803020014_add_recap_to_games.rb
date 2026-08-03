class AddRecapToGames < ActiveRecord::Migration[8.0]
  def change
    add_column :games, :narrative_summary, :string
    add_reference :games, :offensive_player_of_game, foreign_key: { to_table: :student_seasons }
    add_column :games, :offensive_player_stat_line, :string
    add_reference :games, :defensive_player_of_game, foreign_key: { to_table: :student_seasons }
    add_column :games, :defensive_player_stat_line, :string
  end
end
