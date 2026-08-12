class Injury < ApplicationRecord
  belongs_to :student_season
  belongs_to :game

  validates :description, presence: true
  validates :weeks_out, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validate :game_matches_college

  # The week within the same season this player is projected back for, or
  # nil if that would fall beyond the season's last week ("out for season") —
  # computed on read rather than stored, same convention as
  # CollegeSeason#margin_of_victory/#point_differential, so it can never
  # drift from the underlying game/week data.
  def return_week_number
    game.week.number + weeks_out
  end

  def return_week
    game.week.season.weeks.find_by(number: return_week_number)
  end

  def out_for_season?
    return_week.nil?
  end

  # Whether this injury happened by the given week and hasn't been
  # returned from as of that week (or is out for the season) — the shared
  # "still hurt" predicate used anywhere a week-scoped injury report is
  # shown (weekly recap, dashboard next-game banner).
  def active_as_of?(week)
    game.week.number <= week.number && (out_for_season? || return_week_number > week.number)
  end

  private

  def game_matches_college
    return if game.blank? || student_season.blank?

    college_id = student_season.college_season.college_id
    return if [ game.home_college_id, game.away_college_id ].include?(college_id)

    errors.add(:game, "must be a game this player's team played in")
  end
end
