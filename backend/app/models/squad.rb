class Squad < ApplicationRecord
  belongs_to :team

  has_many :position_boards, dependent: :destroy
  has_many :players, dependent: :nullify

  validates :name, presence: true
end
