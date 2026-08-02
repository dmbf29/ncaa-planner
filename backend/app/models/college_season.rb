class CollegeSeason < ApplicationRecord
  belongs_to :college
  belongs_to :coach, optional: true
  belongs_to :season
  has_many :student_seasons, dependent: :destroy

  validates :wins, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :losses, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
