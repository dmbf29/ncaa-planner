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
  #
  # `transfer` distinguishes a portal transfer in from a traditional HS/JUCO
  # signee — both burn the same scholarship slot, so this one model covers
  # both rather than a parallel table. `class_year` is the screen's CLASS
  # column as-is ("HS" for high school, "JC (JR)"/"JC (SO)" for juco, or a
  # plain class year like "SO"/"JR"/"SR" for a transfer's year at their
  # previous school) — not validated against CollegeSeason's class-year
  # vocabulary since "HS"/"JC (..)" aren't real roster class years.
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
