class PlayerFlag < ApplicationRecord
  belongs_to :player
  belongs_to :flag

  validates :flag_id, uniqueness: { scope: :player_id }
end
