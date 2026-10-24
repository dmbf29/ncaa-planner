class AddExtraDefenseStatsToStudentGameStats < ActiveRecord::Migration[8.0]
  def change
    # Left-side Defense columns that weren't saved before (INT YDS, INT AVG, DEFL)
    # plus the right-hand columns you have to scroll to (FFUMB, FMBREC, FMBYDS, BLOCK, SFTY, TD).
    add_column :student_game_stats, :defense_interceptions_yards, :integer
    add_column :student_game_stats, :defense_interceptions_avg, :float
    add_column :student_game_stats, :defense_deflections, :integer
    add_column :student_game_stats, :defense_forced_fumbles, :integer
    add_column :student_game_stats, :defense_fumble_recoveries, :integer
    add_column :student_game_stats, :defense_fumble_return_yards, :integer
    add_column :student_game_stats, :defense_blocks, :integer
    add_column :student_game_stats, :defense_safeties, :integer
    add_column :student_game_stats, :defense_touchdowns, :integer
  end
end
