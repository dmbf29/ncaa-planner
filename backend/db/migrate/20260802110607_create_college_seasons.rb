class CreateCollegeSeasons < ActiveRecord::Migration[8.0]
  def change
    create_table :college_seasons do |t|
      t.integer :wins, null: false, default: 0
      t.integer :losses, null: false, default: 0
      t.integer :offense
      t.integer :defense
      t.float :prestige
      t.integer :final_ranking
      t.integer :recruiting_rank
      t.references :college, null: false, foreign_key: true
      t.references :coach, foreign_key: true
      t.references :season, null: false, foreign_key: true

      t.timestamps
    end
  end
end
