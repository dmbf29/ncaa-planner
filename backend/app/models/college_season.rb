class CollegeSeason < ApplicationRecord
  OFFENSE_POSITIONS = %w[QB HB FB WR TE LT LG C RG RT].freeze
  DEFENSE_POSITIONS = %w[CB DT FS LE RE LOLB MLB ROLB SS].freeze

  POSITION_GROUPS = {
    "Quarterbacks" => %w[QB],
    "Running Backs" => %w[HB FB],
    "Wide Receivers" => %w[WR],
    "Tight Ends" => %w[TE],
    "Offensive Line" => %w[LT LG C RG RT],
    "Defensive Line" => %w[LE RE DT],
    "Linebackers" => %w[MLB LOLB ROLB],
    "Secondary" => %w[CB FS SS],
    "Kickers/Punters" => %w[K P]
  }.freeze

  belongs_to :college
  belongs_to :coach, optional: true
  belongs_to :season
  has_many :student_seasons, dependent: :destroy

  def games
    Game.where(week_id: season.week_ids)
        .where("home_college_id = :id OR away_college_id = :id", id: college_id)
  end

  def best_offensive_players(limit: 3)
    student_seasons.where(position: OFFENSE_POSITIONS).order(overall: :desc).limit(limit)
  end

  def best_defensive_players(limit: 3)
    student_seasons.where(position: DEFENSE_POSITIONS).order(overall: :desc).limit(limit)
  end

  def position_group_averages
    POSITION_GROUPS.transform_values do |positions|
      average = student_seasons.where(position: positions).average(:overall)
      average&.round
    end
  end
end
