class AddBioToStudentSeasons < ActiveRecord::Migration[8.0]
  def change
    add_column :student_seasons, :archetype, :string
    add_column :student_seasons, :height_inches, :integer
    add_column :student_seasons, :weight_lbs, :integer
  end
end
