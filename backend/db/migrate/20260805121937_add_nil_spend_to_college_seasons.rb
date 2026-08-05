class AddNilSpendToCollegeSeasons < ActiveRecord::Migration[8.0]
  def change
    add_column :college_seasons, :nil_spend, :integer
    add_column :college_seasons, :nil_spend_by_position, :jsonb, default: {}, null: false
  end
end
