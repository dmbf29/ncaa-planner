class StudentGameStat < ApplicationRecord
  belongs_to :game
  belongs_to :student_season

  validates :student_season_id, uniqueness: { scope: :game_id }
end
