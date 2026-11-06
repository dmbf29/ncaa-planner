class AddScoringSummaryToGames < ActiveRecord::Migration[8.0]
  def change
    add_column :games, :scoring_summary, :jsonb
  end
end
