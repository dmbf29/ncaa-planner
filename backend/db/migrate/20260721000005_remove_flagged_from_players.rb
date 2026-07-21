class RemoveFlaggedFromPlayers < ActiveRecord::Migration[8.0]
  def up
    remove_column :players, :flagged
  end

  def down
    add_column :players, :flagged, :boolean, default: false, null: false
  end
end
