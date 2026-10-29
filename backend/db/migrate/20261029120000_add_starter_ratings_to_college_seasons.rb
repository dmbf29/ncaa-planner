class AddStarterRatingsToCollegeSeasons < ActiveRecord::Migration[8.0]
  def change
    add_column :college_seasons, :starter_overall, :float
    add_column :college_seasons, :starter_offense, :float
    add_column :college_seasons, :starter_defense, :float
  end
end
