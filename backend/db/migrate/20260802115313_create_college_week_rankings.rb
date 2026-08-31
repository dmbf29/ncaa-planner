class CreateCollegeWeekRankings < ActiveRecord::Migration[8.0]
  def change
    create_table :college_week_rankings do |t|
      t.references :college, null: false, foreign_key: true
      t.references :week, null: false, foreign_key: true
      t.integer :ranking, null: false

      t.index [:week_id, :college_id], unique: true, name: "index_college_week_rankings_on_week_and_college"

      t.timestamps
    end
  end
end
