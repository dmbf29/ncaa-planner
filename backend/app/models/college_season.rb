class CollegeSeason < ApplicationRecord
  belongs_to :college
  belongs_to :coach, optional: true
  belongs_to :season
  has_many :student_seasons, dependent: :destroy
end
