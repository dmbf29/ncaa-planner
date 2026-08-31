class RecruitingSeason < ApplicationRecord
  belongs_to :college_season

  validates :college_season_id, uniqueness: true
end
