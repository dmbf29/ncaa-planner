class CollegeWeekRanking < ApplicationRecord
  belongs_to :college
  belongs_to :week

  validates :ranking, presence: true, uniqueness: { scope: :week }
  validates :college, uniqueness: { scope: :week }
  validates :ranking, uniqueness: { scope: :week }
end
