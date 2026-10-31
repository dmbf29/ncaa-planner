class CollegeGameStat < ApplicationRecord
  belongs_to :game
  belongs_to :college

  validates :college_id, uniqueness: { scope: :game_id }

  # A season's records and points are worked out from its played games (StandingsCalculator), so any score
  # change brings both teams' stored standings up to date.
  after_save :refresh_standings, if: :saved_change_to_final_score?
  after_destroy :refresh_standings, unless: :destroyed_by_association

  private

  def refresh_standings
    season = game.week.season
    StandingsCalculator.refresh(season, [ game.home_college_id, game.away_college_id ])
  end
end
