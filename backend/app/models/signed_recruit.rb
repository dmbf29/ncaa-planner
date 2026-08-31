class SignedRecruit < ApplicationRecord
  # An individual recruit who signed with a coached program during a
  # season, read off the recruiting-class screen. Distinct from
  # RecruitingSeason (which is the team-level class summary — rank, points,
  # star counts) and from StudentSeason (a player actually on a roster with
  # an overall/dev-trait): a signee hasn't enrolled yet, arriving the
  # following season.
  #
  # `week` is the week the signing was first recorded, not a week the
  # recruit did anything — it's what lets the weekly podcast surface "newly
  # signed this week" without re-mentioning earlier signings. Same
  # observation-week convention as BowlProjection.
  belongs_to :college_season
  belongs_to :week
  belongs_to :student, optional: true

  validates :last_name, presence: true
  validates :position, presence: true
  validates :star_rating, inclusion: { in: 1..5 }, allow_nil: true

  def name
    [ first_name, last_name ].compact_blank.join(" ").strip
  end
end
