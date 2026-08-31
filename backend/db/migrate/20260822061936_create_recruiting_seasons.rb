class CreateRecruitingSeasons < ActiveRecord::Migration[8.0]
  def change
    create_table :recruiting_seasons do |t|
      t.references :college_season, null: false, foreign_key: true, index: { unique: true }
      t.integer :ranking
      t.float :points
      t.integer :total_signed
      t.integer :nil_spent
      t.integer :five_stars
      t.integer :four_stars
      t.integer :three_stars
      t.integer :two_stars
      t.integer :one_stars

      t.timestamps
    end
  end
end
