class CreateInjuries < ActiveRecord::Migration[8.0]
  def change
    create_table :injuries do |t|
      t.references :student_season, null: false, foreign_key: true
      t.references :game, null: false, foreign_key: true
      t.string :description, null: false
      t.integer :weeks_out, null: false

      t.timestamps
    end
  end
end
