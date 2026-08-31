class AddByeWeekIdsToCollegeSeasons < ActiveRecord::Migration[8.0]
  def change
    add_column :college_seasons, :bye_week_ids, :jsonb, default: [], null: false
  end
end
