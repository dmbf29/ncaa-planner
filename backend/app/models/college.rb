class College < ApplicationRecord
  has_many :teams
  validates :name, presence: true, uniqueness: true

  def scraping_url
    "https://www.teamcrafters.net/rosters/CFB27/launch-6-30-26/#{api_id}"
  end
end
