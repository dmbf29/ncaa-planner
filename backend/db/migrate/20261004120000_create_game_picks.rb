class CreateGamePicks < ActiveRecord::Migration[8.0]
  def change
    create_table :game_picks do |t|
      t.references :game, null: false, foreign_key: true
      t.string :host, null: false
      t.string :market, null: false
      t.string :side, null: false
      t.decimal :spread_line, precision: 4, scale: 1, null: false
      t.decimal :total_line, precision: 4, scale: 1, null: false

      t.timestamps
    end

    add_index :game_picks, %i[game_id host], unique: true
  end
end
