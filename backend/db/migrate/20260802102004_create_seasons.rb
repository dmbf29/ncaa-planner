class CreateSeasons < ActiveRecord::Migration[8.0]
  def change
    create_table :seasons do |t|
      t.integer :year, null: false
      t.references :dynasty, null: false, foreign_key: true

      t.timestamps
    end
  end
end
