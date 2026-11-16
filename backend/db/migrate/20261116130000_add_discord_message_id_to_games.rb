class AddDiscordMessageIdToGames < ActiveRecord::Migration[8.0]
  def change
    # The Discord post for this game's videos, kept so it can be edited when the second video is uploaded.
    add_column :games, :discord_message_id, :string
  end
end
