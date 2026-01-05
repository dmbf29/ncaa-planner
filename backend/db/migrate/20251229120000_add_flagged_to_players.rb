class AddFlaggedToPlayers < ActiveRecord::Migration[8.0]
  def change
    add_column :players, :flagged, :boolean, default: false, null: false
  end
end
