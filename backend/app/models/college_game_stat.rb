class CollegeGameStat < ApplicationRecord
  belongs_to :game
  belongs_to :college

  validates :college_id, uniqueness: { scope: :game_id }
end
