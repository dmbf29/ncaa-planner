class AddOffseasonCoachToCollegeSeasons < ActiveRecord::Migration[8.0]
  def change
    add_reference :college_seasons, :offseason_coach, foreign_key: { to_table: :coaches }, index: true
  end
end
