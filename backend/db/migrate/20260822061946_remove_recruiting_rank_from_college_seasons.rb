class RemoveRecruitingRankFromCollegeSeasons < ActiveRecord::Migration[8.0]
  def change
    remove_column :college_seasons, :recruiting_rank, :integer
  end
end
