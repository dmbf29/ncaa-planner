class CreateAwards < ActiveRecord::Migration[8.0]
  def change
    create_table :awards do |t|
      t.string :name, null: false
      t.text :description
      # "player" -> won by a StudentSeason, "coach" -> won by a Coach.
      # Drives which picker the Award Winners page shows and which FK
      # SeasonAward is allowed to set.
      t.string :recipient_type, null: false, default: "player"
      t.integer :sort_order, null: false, default: 0
      t.timestamps
    end
    add_index :awards, :name, unique: true
  end
end
