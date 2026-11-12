class AddRankedToScheduleOptions < ActiveRecord::Migration[8.0]
  def change
    add_column :schedule_options, :ranked, :boolean, default: false, null: false
  end
end
