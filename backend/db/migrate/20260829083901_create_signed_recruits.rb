class CreateSignedRecruits < ActiveRecord::Migration[8.0]
  def change
    create_table :signed_recruits do |t|
      t.references :college_season, null: false, foreign_key: true
      t.references :week, null: false, foreign_key: true
      # Nullable — linked once the recruit enrolls and gets a StudentSeason
      # (roster import), so the same person can be followed from signing
      # into their playing career. Not populated yet.
      t.references :student, foreign_key: true

      # The screenshot only shows a first initial; first_name is filled in
      # by hand on the review screen so it can be matched by name next
      # season when the roster is imported.
      t.string :first_name
      t.string :last_name, null: false
      t.string :position, null: false
      t.integer :star_rating
      t.integer :nil_amount
      t.integer :national_rank
      t.integer :position_rank
      t.integer :state_rank
      t.string :state

      t.timestamps
    end
  end
end
