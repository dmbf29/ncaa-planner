# One rostered player's outlook heading into the transfer portal, read off
# the "players leaving" screen for a coached team at the end of a season.
# A full roster's screen is many pages long, so it's expected to be
# uploaded across several separate sessions — each upload upserts rather
# than replacing the college_season's whole set (see
# PortalPreview::CommitService), so an earlier upload's players survive a
# later, different upload for the same team.
#
# student_season is nullable: the screen only shows a first initial + last
# name, so a row that can't be confidently matched to this college_season's
# current roster is still saved (raw first_initial/last_name/position/
# class_year/overall as read off the screen) rather than dropped, since
# it's still useful context even unmatched.
class PortalStatus < ApplicationRecord
  STATUSES = %w[transfer pro_draft staying graduation].freeze

  # "not_applicable" is the on-screen dash ("---") — shown for players who
  # have no remaining eligibility to persuade (typically a senior who's
  # graduating or already exhausted eligibility going pro), distinct from
  # "none" (0% chance, but still technically has eligibility left).
  PERSUASION_LEVELS = %w[
    not_applicable none extremely_low very_low low medium high very_high extremely_high guaranteed
  ].freeze

  belongs_to :college_season
  belongs_to :student_season, optional: true

  validates :last_name, presence: true
  validates :position, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :persuasion_chance, inclusion: { in: PERSUASION_LEVELS }, allow_nil: true

  def display_name
    [ first_initial.present? ? "#{first_initial}." : nil, last_name ].compact.join(" ")
  end
end
