class RosterSlot < ApplicationRecord
  belongs_to :position_board
  belongs_to :player

  validates :slot_number, presence: true
  validate :player_team_matches_board

  private

  def player_team_matches_board
    return if player.blank? || position_board.blank?
    return if player.team_id == position_board.team_id

    errors.add(:player_id, "must belong to the same team as the position board")
  end
end
