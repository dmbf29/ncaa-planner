class AddTwitchNameToCoaches < ActiveRecord::Migration[8.0]
  def change
    add_column :coaches, :twitch_name, :string
  end
end
