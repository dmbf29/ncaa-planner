class CollegeWeekRanking < ApplicationRecord
  belongs_to :college
  belongs_to :week

  validates :ranking, presence: true
  validates :college_id, uniqueness: { scope: :week_id }
end
