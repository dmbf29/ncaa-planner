class AddConferenceStandingsToCollegeSeasons < ActiveRecord::Migration[8.0]
  def change
    add_column :college_seasons, :conference_wins, :integer
    add_column :college_seasons, :conference_losses, :integer
    add_column :college_seasons, :conference_points_for, :integer
    add_column :college_seasons, :conference_points_against, :integer
    add_column :college_seasons, :points_for, :integer
    add_column :college_seasons, :points_against, :integer
    add_column :college_seasons, :home_wins, :integer
    add_column :college_seasons, :home_losses, :integer
  end
end
