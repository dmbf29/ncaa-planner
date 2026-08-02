class UpdateAttrsInCollegeSeasons < ActiveRecord::Migration[8.0]
  def change
    add_column :college_seasons, :overall, :integer
    remove_column :college_seasons, :wins
    remove_column :college_seasons, :losses
    remove_column :college_seasons, :final_ranking
    add_column :college_seasons, :wins, :integer
    add_column :college_seasons, :losses, :integer
  end
end
