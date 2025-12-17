class CreatePositionBoards < ActiveRecord::Migration[8.0]
  def change
    create_table :position_boards do |t|
      t.string :name, null: false
      t.integer :slots_count, null: false, default: 0
      t.jsonb :highlighted_attributes, null: false, default: []
      t.jsonb :target_archetypes, null: false, default: []
      t.text :notes
      t.references :team, null: false, foreign_key: true
      t.references :squad, null: false, foreign_key: true

      t.timestamps
    end
  end
end
