class CreateStudentSeasons < ActiveRecord::Migration[8.0]
  def change
    create_table :student_seasons do |t|
      t.string :class_year, null: false
      t.string :position, null: false
      t.integer :overall
      t.integer :nil_amount
      t.string :dev_trait
      t.integer :speed
      t.references :student, null: false, foreign_key: true
      t.references :college_season, null: false, foreign_key: true

      t.timestamps
    end
  end
end
