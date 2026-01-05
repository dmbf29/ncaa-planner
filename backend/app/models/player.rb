class Player < ApplicationRecord
  belongs_to :team
  belongs_to :squad, optional: true
  belongs_to :position_board, optional: true

  has_one :roster_slot, dependent: :destroy
  has_many :replacement_needs, class_name: "Need", foreign_key: :replacement_player_id, dependent: :nullify
  has_many :departing_needs, class_name: "Need", foreign_key: :departing_player_id, dependent: :nullify

  enum :status, { recruit: 0, rostered: 1, graduated: 2, departed: 3 }
  enum :recruit_status, { normal: 0, gem: 1, bust: 2 }, default: :normal

  validates :name, presence: true
  before_validation :sync_squad_from_position_board
  validate :squad_belongs_to_team
  validate :position_board_belongs_to_team
  before_validation :ensure_defaults

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

  def ensure_defaults
    self.attribute_values ||= {}
    self.abilities ||= []
    self.tags ||= []
    self.recruit_status ||= "normal"
    self.flagged = false if flagged.nil?
  end

  def sync_squad_from_position_board
    return if position_board.blank?

    # Keep squad aligned with the position board so roster moves do not orphan players
    self.squad_id = position_board.squad_id
  end

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
