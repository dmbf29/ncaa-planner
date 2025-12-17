class Player < ApplicationRecord
  belongs_to :team
  belongs_to :squad, optional: true
  belongs_to :position_board, optional: true

  has_one :roster_slot, dependent: :destroy

  enum :status, { recruit: 0, rostered: 1, graduated: 2, departed: 3 }

  validates :name, presence: true
  validate :squad_belongs_to_team
  validate :position_board_belongs_to_team

  def attributes_payload
    attribute_values
  end

  def as_json(options = {})
    super(options).tap do |hash|
      hash["attributes"] = attribute_values
      hash.delete("attribute_values")
    end
  end

  private

  def squad_belongs_to_team
    return if squad.blank?
    return if squad.team_id == team_id

    errors.add(:squad_id, "must belong to the same team")
  end

  def position_board_belongs_to_team
    return if position_board.blank?
    return if position_board.team_id == team_id

    errors.add(:position_board_id, "must belong to the same team")
  end
end
