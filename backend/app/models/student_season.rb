class StudentSeason < ApplicationRecord
  belongs_to :student
  belongs_to :college_season
  has_many :student_game_stats, dependent: :destroy

  validates :class_year, presence: true
  validates :position, presence: true
end
