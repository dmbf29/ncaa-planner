class AddDivisionToCollegeSeasons < ActiveRecord::Migration[8.0]
  def change
    add_column :college_seasons, :division, :string
  end
end
