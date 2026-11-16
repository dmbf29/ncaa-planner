class AddKindToGameVideos < ActiveRecord::Migration[8.0]
  def change
    # "full" is the whole recorded game; "highlights" is the short cut of its scoring plays.
    add_column :game_videos, :kind, :string, null: false, default: "full"
  end
end
