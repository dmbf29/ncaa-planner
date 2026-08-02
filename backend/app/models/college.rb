class College < ApplicationRecord
  has_many :teams
  has_many :college_seasons, dependent: :destroy
  has_many :college_week_rankings, dependent: :destroy
  has_many :student_seasons, through: :college_seasons

  validates :name, presence: true, uniqueness: true

  def scraping_url
    "https://www.teamcrafters.net/rosters/CFB27/launch-6-30-26/#{api_id}"
  end
end
