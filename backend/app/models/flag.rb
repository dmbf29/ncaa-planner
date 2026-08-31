class Flag < ApplicationRecord
  has_many :player_flags, dependent: :destroy
  has_many :players, through: :player_flags

  validates :name, presence: true, uniqueness: true
  validates :icon, presence: true
  validates :color, presence: true
end
