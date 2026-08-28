class Week < ApplicationRecord
  belongs_to :season
  has_many :games, dependent: :destroy
  has_many :college_week_rankings, dependent: :destroy
  has_many :heisman_candidates, dependent: :destroy
  has_many :players_of_the_week, class_name: "PlayerOfTheWeek", dependent: :destroy
  has_many :bowl_projections, dependent: :destroy

  validates :number, presence: true, uniqueness: { scope: :season }
end
