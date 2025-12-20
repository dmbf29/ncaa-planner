class CreateNeeds < ActiveRecord::Migration[8.0]
  def change
    create_table :needs do |t|
      t.references :position_board, null: false, foreign_key: true
      t.references :replacement_player, null: true, foreign_key: { to_table: :players }
      t.references :departing_player, null: true, foreign_key: { to_table: :players }
      t.integer :slot_number, null: true
      t.boolean :resolved, null: false, default: false

      t.timestamps
    end

    add_index :needs, [:position_board_id, :slot_number],
              unique: true,
              where: "slot_number IS NOT NULL"
  end
end
