class Student < ApplicationRecord
  has_many :student_seasons, dependent: :destroy

  validates :first_name, presence: true
  validates :last_name, presence: true
end
