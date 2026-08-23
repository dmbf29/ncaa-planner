class AddTeamStatsToCollegeSeasons < ActiveRecord::Migration[8.0]
  def change
    add_column :college_seasons, :points_scored, :integer
    add_column :college_seasons, :total_offensive_yards, :integer
    add_column :college_seasons, :yards_per_play, :float
    add_column :college_seasons, :passing_yards, :integer
    add_column :college_seasons, :passing_touchdowns, :integer
    add_column :college_seasons, :rushing_yards, :integer
    add_column :college_seasons, :rushing_touchdowns, :integer
    add_column :college_seasons, :first_downs, :integer

    add_column :college_seasons, :points_allowed, :integer
    add_column :college_seasons, :total_yards_allowed, :integer
    add_column :college_seasons, :passing_yards_allowed, :integer
    add_column :college_seasons, :rushing_yards_allowed, :integer
    add_column :college_seasons, :defensive_sacks, :integer
    add_column :college_seasons, :fumble_recoveries, :integer
    add_column :college_seasons, :defensive_interceptions, :integer
  end
end
