class AddBowlFieldsToGames < ActiveRecord::Migration[8.0]
  def change
    add_column :games, :bowl_name, :string
    add_column :games, :cfp_round, :integer
  end
end
