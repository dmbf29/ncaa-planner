class AddAdditionalContextToGames < ActiveRecord::Migration[8.0]
  def change
    add_column :games, :additional_context, :text
  end
end
