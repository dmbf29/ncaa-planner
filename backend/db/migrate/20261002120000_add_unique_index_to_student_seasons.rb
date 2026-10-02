class AddUniqueIndexToStudentSeasons < ActiveRecord::Migration[8.0]
  def change
    add_index :student_seasons, %i[student_id college_season_id], unique: true
  end
end
