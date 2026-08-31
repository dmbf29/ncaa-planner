class Dynasty < ApplicationRecord
  belongs_to :user
  has_many :seasons, dependent: :destroy
  has_many :coaches, dependent: :destroy

  validates :name, presence: true
end
