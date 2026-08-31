class AllAmerican < ApplicationRecord
  TIERS = [ 1, 2 ].freeze

  belongs_to :student_season

  validates :tier, inclusion: { in: TIERS }
  validates :conference, presence: true, unless: :national
  validates :conference, absence: true, if: :national
  validates :student_season, uniqueness: { scope: %i[national conference preseason] }
end
