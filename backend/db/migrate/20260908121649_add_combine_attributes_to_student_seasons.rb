class AddCombineAttributesToStudentSeasons < ActiveRecord::Migration[8.0]
  def change
    add_column :student_seasons, :acceleration, :integer
    add_column :student_seasons, :agility, :integer
    add_column :student_seasons, :change_of_direction, :integer
    add_column :student_seasons, :strength, :integer
    add_column :student_seasons, :awareness, :integer
  end
end
