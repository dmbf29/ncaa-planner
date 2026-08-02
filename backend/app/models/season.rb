class Season < ApplicationRecord
  belongs_to :dynasty
  belongs_to :heisman, class_name: "StudentSeason", optional: true
  has_many :weeks, dependent: :destroy
  has_many :college_seasons, dependent: :destroy

  validates :year, presence: true
end
