class Week < ApplicationRecord
  belongs_to :season
  has_many :games, dependent: :destroy
  has_many :college_week_rankings, dependent: :destroy

  validates :number, presence: true, uniqueness: { scope: :season }
end
