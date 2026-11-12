# A coach's chosen opponent for one open week. Becomes a real Game when the coach confirms (Scheduling::PickRules#confirm!).
# When the opponent is another coach's team, a second pick is made on that team's schedule (mirrored_from points back
# at the original) so the shared game shows on both and only the coach who chose it can change it.
class SchedulePick < ApplicationRecord
  belongs_to :college_season
  belongs_to :week
  belongs_to :opponent_college, class_name: "College"
  belongs_to :mirrored_from, class_name: "SchedulePick", optional: true
  has_one :mirror, class_name: "SchedulePick", foreign_key: :mirrored_from_id, dependent: :destroy, inverse_of: :mirrored_from

  validates :week_id, uniqueness: { scope: :college_season_id }

  def mirrored? = mirrored_from_id.present?
end
