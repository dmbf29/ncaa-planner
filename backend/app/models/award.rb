class Award < ApplicationRecord
  RECIPIENT_TYPES = %w[player coach].freeze

  has_many :season_awards, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :recipient_type, inclusion: { in: RECIPIENT_TYPES }

  scope :ordered, -> { order(:sort_order, :name) }
  scope :for_players, -> { where(recipient_type: "player") }
  scope :for_coaches, -> { where(recipient_type: "coach") }

  def player_award?
    recipient_type == "player"
  end

  def coach_award?
    recipient_type == "coach"
  end
end
