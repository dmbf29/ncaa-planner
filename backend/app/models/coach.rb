class Coach < ApplicationRecord
  belongs_to :dynasty
  has_many :college_seasons, dependent: :nullify

  validates :name, presence: true
end
