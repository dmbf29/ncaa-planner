class HeismanCandidate < ApplicationRecord
  belongs_to :week
  belongs_to :student_season

  validates :student_season, uniqueness: { scope: :week }
end
