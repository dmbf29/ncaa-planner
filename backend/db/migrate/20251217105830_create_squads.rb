class CreateSquads < ActiveRecord::Migration[8.0]
  def change
    create_table :squads do |t|
      t.string :name, null: false
      t.references :team, null: false, foreign_key: true

      t.timestamps
    end
    add_index :squads, [:team_id, :name], unique: true
  end
end
