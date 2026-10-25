class CollegeSeason < ApplicationRecord
  OFFENSE_POSITIONS = %w[QB HB FB WR TE LT LG C RG RT].freeze
  DEFENSE_POSITIONS = %w[CB DT FS LE RE LEDG REDG LOLB MLB ROLB SS MIKE WILL SAM].freeze
  UNDERCLASS_YEARS = %w[FR FR(RS) SO SO(RS)].freeze
  BREAKOUT_DEV_TRAITS = %w[star elite].freeze

  POSITION_GROUPS = {
    "Quarterbacks" => %w[QB],
    "Running Backs" => %w[HB FB],
    "Wide Receivers" => %w[WR],
    "Tight Ends" => %w[TE],
    "Offensive Line" => %w[LT LG C RG RT],
    "Defensive Line" => %w[LE RE LEDG REDG DT],
    "Linebackers" => %w[MLB LOLB ROLB MIKE WILL SAM],
    "Secondary" => %w[CB FS SS],
    "Kickers/Punters" => %w[K P]
  }.freeze

  # What happened to this season's coach once the season ended. nil means not
  # recorded yet. Where a fired/departed coach lands is not stored: it shows up
  # as coach_id on another college's CollegeSeason the following season.
  enum :coach_outcome, { continued: 0, fired: 1, left: 2 }, prefix: :coach, validate: { allow_nil: true }

  belongs_to :college
  belongs_to :coach, optional: true
  # Who runs this program for the offseason that follows the season (portal,
  # signing day), set when a coach moves schools after the season ends. The
  # season's own coach_id stays put so the season's recaps and report cards
  # keep the coach who actually coached it. See #offseason_coach_record.
  belongs_to :offseason_coach, class_name: "Coach", optional: true, inverse_of: :offseason_college_seasons
  belongs_to :season
  has_many :student_seasons, dependent: :destroy
  has_many :signed_recruits, dependent: :destroy
  has_many :portal_statuses, dependent: :destroy
  has_one :recruiting_season, dependent: :destroy
  validates :season, uniqueness: { scope: :college }
  validates :coach_id, uniqueness: { scope: :season_id }, allow_nil: true
  validates :offseason_coach_id, uniqueness: { scope: :season_id }, allow_nil: true

  # Programs with a coach of ours for the offseason: a coach who was fired or
  # left no longer holds their old program, so it only counts if someone was
  # moved in; everyone else keeps theirs unless replaced.
  OFFSEASON_COACH_SQL = "CASE WHEN college_seasons.coach_outcome IN (1, 2) THEN college_seasons.offseason_coach_id " \
                        "ELSE COALESCE(college_seasons.offseason_coach_id, college_seasons.coach_id) END".freeze
  scope :offseason_coached, -> { where("#{OFFSEASON_COACH_SQL} IS NOT NULL") }

  def offseason_coach_record
    return offseason_coach if offseason_coach_id
    return nil if coach_fired? || coach_left?

    coach
  end

  def games
    Game.where(week_id: season.week_ids)
        .where("home_college_id = :id OR away_college_id = :id", id: college_id)
  end

  def opponent_college_seasons
    opponent_college_ids = games.where(home_college_id: college_id).pluck(:away_college_id) +
                            games.where(away_college_id: college_id).pluck(:home_college_id)
    season.college_seasons.where(college_id: opponent_college_ids)
  end

  def best_offensive_players(limit: 3)
    student_seasons.where(position: OFFENSE_POSITIONS).includes(:student).order(overall: :desc).limit(limit)
  end

  def best_defensive_players(limit: 3)
    student_seasons.where(position: DEFENSE_POSITIONS).includes(:student).order(overall: :desc).limit(limit)
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
