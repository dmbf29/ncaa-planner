class CollegeSeason < ApplicationRecord
  OFFENSE_POSITIONS = %w[QB HB FB WR TE LT LG C RG RT].freeze
  DEFENSE_POSITIONS = %w[CB DT FS LE RE LOLB MLB ROLB SS].freeze
  UNDERCLASS_YEARS = %w[FR FR(RS) SO SO(RS)].freeze
  BREAKOUT_DEV_TRAITS = %w[star elite].freeze

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
  validates :season, uniqueness: { scope: :college }

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

  def most_valuable_player
    student_seasons.order(overall: :desc).first
  end

  def breakout_candidate
    student_seasons.where(dev_trait: BREAKOUT_DEV_TRAITS, class_year: UNDERCLASS_YEARS)
                    .order(overall: :desc)
                    .first
  end

  def point_differential
    return nil if points_for.nil? || points_against.nil?

    points_for - points_against
  end

  def margin_of_victory
    return nil if points_for.nil? || points_against.nil?

    games_played = wins.to_i + losses.to_i
    return nil if games_played.zero?

    (points_for - points_against) / games_played.to_f
  end

  def away_wins
    return nil if wins.nil? || home_wins.nil?

    wins - home_wins
  end

  def away_losses
    return nil if losses.nil? || home_losses.nil?

    losses - home_losses
  end
end
