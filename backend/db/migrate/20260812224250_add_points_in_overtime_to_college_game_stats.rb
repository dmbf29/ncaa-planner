class AddPointsInOvertimeToCollegeGameStats < ActiveRecord::Migration[8.0]
  def change
    add_column :college_game_stats, :points_in_overtime, :integer
  end
end
