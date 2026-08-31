class CreateWeeks < ActiveRecord::Migration[8.0]
  def change
    create_table :weeks do |t|
      t.integer :number, null: false
      t.string :name
      t.references :season, null: false, foreign_key: true
      t.boolean :conference_championship, null: false, default: false
      t.boolean :post_season, null: false, default: false

      t.timestamps
    end
  end
end
