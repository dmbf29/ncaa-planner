class CreateBowlProjections < ActiveRecord::Migration[8.0]
  def change
    create_table :bowl_projections do |t|
      t.references :week, null: false, foreign_key: true
      t.string :bowl_name, null: false
      t.integer :cfp_round
      # Nullable: a projection is often published before both slots are known (e.g. "Group of 5 champion TBD").
      t.references :projected_home_college, foreign_key: { to_table: :colleges }
      t.references :projected_away_college, foreign_key: { to_table: :colleges }

      t.timestamps
    end
  end
end
