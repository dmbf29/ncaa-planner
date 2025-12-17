class Team < ApplicationRecord
  belongs_to :user

  has_many :squads, dependent: :destroy
  has_many :position_boards, dependent: :destroy
  has_many :players, dependent: :destroy

  validates :name, presence: true

  accepts_nested_attributes_for :squads, allow_destroy: false
end
