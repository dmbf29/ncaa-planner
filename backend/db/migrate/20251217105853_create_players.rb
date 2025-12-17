class CreatePlayers < ActiveRecord::Migration[8.0]
  def change
    create_table :players do |t|
      t.string :name, null: false
      t.string :class_year
      t.string :dev_trait
      t.string :archetype
      t.integer :status, null: false, default: 0
      t.integer :star_rating
      t.string :eval_status
      t.integer :overall
      t.jsonb :attribute_values, null: false, default: {}
      t.jsonb :abilities, null: false, default: []
      t.jsonb :tags, null: false, default: []
      t.text :notes
      t.boolean :pursued, null: false, default: false
      t.boolean :signed, null: false, default: false
      t.boolean :position_change_needed, null: false, default: false
      t.references :team, null: false, foreign_key: true
      t.references :squad, foreign_key: true
      t.references :position_board, foreign_key: true

      t.timestamps
    end
    add_index :players, [:team_id, :status]
    add_index :players, [:position_board_id, :status]
  end
end
