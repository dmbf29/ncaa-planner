class SeasonAward < ApplicationRecord
  belongs_to :season
  belongs_to :award
  belongs_to :student_season, optional: true
  belongs_to :coach, optional: true

  validates :award_id, uniqueness: { scope: :season_id }
  validate :exactly_one_recipient
  validate :recipient_matches_award_type
  validate :student_season_belongs_to_season
  validate :coach_belongs_to_dynasty

  # The player (StudentSeason) or coach (Coach) that won this award.
  def recipient
    student_season || coach
  end

  def recipient_name
    student_season&.student&.name || coach&.name
  end

  private

  def exactly_one_recipient
    return if student_season.present? ^ coach.present?

    errors.add(:base, "must have exactly one recipient (a player or a coach)")
  end

  def recipient_matches_award_type
    return if award.blank?

    if award.player_award? && coach.present?
      errors.add(:coach, "can't win a player award")
    elsif award.coach_award? && student_season.present?
      errors.add(:student_season, "can't win a coach award")
    end
  end

  def student_season_belongs_to_season
    return if student_season.blank? || season.blank?
    return if student_season.college_season&.season_id == season_id

    errors.add(:student_season, "is not part of this season")
  end

  def coach_belongs_to_dynasty
    return if coach.blank? || season.blank?
    return if coach.dynasty_id == season.dynasty_id

    errors.add(:coach, "is not part of this dynasty")
  end
end
