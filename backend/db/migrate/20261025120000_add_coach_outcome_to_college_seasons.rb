class AddCoachOutcomeToCollegeSeasons < ActiveRecord::Migration[8.0]
  def change
    add_column :college_seasons, :coach_outcome, :integer
  end
end
