class AddScheduling < ActiveRecord::Migration[8.0]
  def change
    add_column :seasons, :schedule_bye_week_numbers, :jsonb, default: [], null: false

    add_column :college_seasons, :schedule_token, :string
    add_column :college_seasons, :schedule_uploaded_at, :datetime
    add_column :college_seasons, :schedule_confirmed_at, :datetime
    add_column :college_seasons, :schedule_locked_week_ids, :jsonb, default: [], null: false
    add_index :college_seasons, :schedule_token, unique: true

    create_table :schedule_options do |t|
      t.references :college_season, null: false, foreign_key: true
      t.references :week, null: false, foreign_key: true
      t.references :opponent_college, null: false, foreign_key: { to_table: :colleges }
      t.integer :rank
      t.boolean :suggested, default: false, null: false
      t.timestamps
    end
    add_index :schedule_options, %i[college_season_id week_id opponent_college_id], unique: true, name: "index_schedule_options_uniqueness"
  end
end
