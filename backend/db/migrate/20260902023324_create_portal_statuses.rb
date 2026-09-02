class CreatePortalStatuses < ActiveRecord::Migration[8.0]
  def change
    create_table :portal_statuses do |t|
      t.references :college_season, null: false, foreign_key: true
      t.references :student_season, foreign_key: true
      t.string :first_initial
      t.string :last_name, null: false
      t.string :position, null: false
      t.string :class_year
      t.integer :overall
      t.string :status, null: false
      t.string :transfer_reason
      t.integer :projected_draft_round
      t.string :persuasion_chance

      t.timestamps
    end
  end
end
