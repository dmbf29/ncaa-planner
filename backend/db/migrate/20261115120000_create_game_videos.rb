class CreateGameVideos < ActiveRecord::Migration[8.0]
  def change
    create_table :game_videos do |t|
      t.references :game, null: false, foreign_key: true
      # "youtube" (source is a video id) or "file" (source is a direct video URL).
      t.string :provider, null: false
      t.string :source, null: false
      t.string :title
      t.integer :duration_seconds
      # Twitch VOD this was made from, so a re-run of the importer never uploads it twice.
      t.string :source_twitch_vod_id
      t.timestamps
    end
    add_index :game_videos, :source_twitch_vod_id, unique: true, where: "source_twitch_vod_id IS NOT NULL"
  end
end
