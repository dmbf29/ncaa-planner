class PositionBoard < ApplicationRecord
  belongs_to :team
  belongs_to :squad

  has_many :players, dependent: :nullify
  has_many :roster_slots, dependent: :destroy

  validates :name, presence: true
  validate :squad_belongs_to_team

  private

  def squad_belongs_to_team
    return if squad.blank? || team.blank?
    return if squad.team_id == team_id

    errors.add(:squad_id, "must belong to the same team")
  end
end
