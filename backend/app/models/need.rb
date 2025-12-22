class Need < ApplicationRecord
  belongs_to :position_board
  belongs_to :replacement_player, class_name: "Player", optional: true
  belongs_to :departing_player, class_name: "Player", optional: true

  validates :resolved, inclusion: { in: [true, false] }
  validates :slot_number, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :slot_or_departing_present
  validate :departing_player_matches_board
  validate :replacement_player_matches_board
  validate :replacement_differs_from_departing

  private

  def slot_or_departing_present
    if departing_player_id.blank? && slot_number.blank?
      errors.add(:base, "needs either a departing player or a slot number")
    elsif departing_player_id.present? && slot_number.present?
      errors.add(:base, "cannot specify both a departing player and a slot number")
    end
  end

  def departing_player_matches_board
    return if departing_player.blank? || position_board.blank?
    return if departing_player.team_id == position_board.team_id

    errors.add(:departing_player_id, "must belong to the same team as the position board")
  end

  def replacement_differs_from_departing
    return if replacement_player_id.blank? || departing_player_id.blank?
    return if replacement_player_id != departing_player_id

    errors.add(:replacement_player_id, "must differ from the departing player")
  end

  def replacement_player_matches_board
    return if replacement_player.blank? || position_board.blank?
    return if replacement_player.team_id == position_board.team_id

    errors.add(:replacement_player_id, "must belong to the same team as the position board")
  end
end
