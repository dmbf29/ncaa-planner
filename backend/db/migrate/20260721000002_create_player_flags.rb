class CreatePlayerFlags < ActiveRecord::Migration[8.0]
  def change
    create_table :player_flags do |t|
      t.references :player, null: false, foreign_key: true
      t.references :flag, null: false, foreign_key: true
      t.timestamps
    end
    add_index :player_flags, [:player_id, :flag_id], unique: true
  end
end
