class CreateAllAmericans < ActiveRecord::Migration[8.0]
  def change
    create_table :all_americans do |t|
      t.references :student_season, null: false, foreign_key: true
      t.boolean :national, null: false, default: false
      t.string :conference
      t.integer :tier, null: false
      t.boolean :preseason, null: false, default: false

      t.timestamps
    end

    add_index :all_americans, %i[student_season_id national conference preseason],
              unique: true, name: "index_all_americans_on_student_season_and_category"
  end
end
