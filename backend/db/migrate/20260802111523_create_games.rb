class CreateGames < ActiveRecord::Migration[8.0]
  def change
    create_table :games do |t|
      t.references :week, null: false, foreign_key: true
      t.datetime :time
      t.references :home_college, null: false, foreign_key: { to_table: :colleges }
      t.references :away_college, null: false, foreign_key: { to_table: :colleges }

      t.check_constraint "home_college_id != away_college_id", name: "games_home_away_college_different"

      t.timestamps
    end
  end
end
