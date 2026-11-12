class CreateSchedulePicks < ActiveRecord::Migration[8.0]
  def change
    create_table :schedule_picks do |t|
      t.references :college_season, null: false, foreign_key: true
      t.references :week, null: false, foreign_key: true
      t.references :opponent_college, null: false, foreign_key: { to_table: :colleges }
      t.boolean :is_away, default: false, null: false
      t.references :mirrored_from, foreign_key: { to_table: :schedule_picks }
      t.timestamps
    end
    add_index :schedule_picks, %i[college_season_id week_id], unique: true
  end
end
