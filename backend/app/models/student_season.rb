class StudentSeason < ApplicationRecord
  belongs_to :student
  belongs_to :college_season
  has_many :student_game_stats, dependent: :destroy
  has_many :all_americans, dependent: :destroy
  has_many :heisman_candidates, dependent: :destroy

  validates :class_year, presence: true
  validates :position, presence: true
end
