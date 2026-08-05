class CreateHeismanCandidates < ActiveRecord::Migration[8.0]
  def change
    create_table :heisman_candidates do |t|
      t.references :week, null: false, foreign_key: true
      t.references :student_season, null: false, foreign_key: true

      t.timestamps
    end

    add_index :heisman_candidates, %i[week_id student_season_id], unique: true, name: "index_heisman_candidates_on_week_and_student_season"
  end
end
