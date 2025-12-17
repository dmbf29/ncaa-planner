class CreateRosterSlots < ActiveRecord::Migration[8.0]
  def change
    create_table :roster_slots do |t|
      t.references :position_board, null: false, foreign_key: true
      t.references :player, null: false, foreign_key: true
      t.integer :slot_number, null: false

      t.timestamps
    end
    add_index :roster_slots, [:position_board_id, :slot_number], unique: true
    add_index :roster_slots, [:position_board_id, :player_id], unique: true
  end
end
