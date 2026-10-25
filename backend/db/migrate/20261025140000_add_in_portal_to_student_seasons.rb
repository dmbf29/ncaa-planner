class AddInPortalToStudentSeasons < ActiveRecord::Migration[8.0]
  def change
    add_column :student_seasons, :in_portal, :boolean, null: false, default: false
  end
end
