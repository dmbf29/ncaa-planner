class Game < ApplicationRecord
  # Bowl week (Week#post_season) games only. cfp_round is nil for both
  # regular-season games and non-playoff bowl games (e.g. "Alamo Bowl") —
  # only games in the actual College Football Playoff bracket get one.
  # first_round/quarterfinal/semifinal/championship line up 1:1 with the
  # four post-season weeks Season#create_weeks generates ("Bowl Week 1"-4),
  # and championship doubles as the national championship marker since
  # it's always that bracket's last round.
  enum :cfp_round, { first_round: 0, quarterfinal: 1, semifinal: 2, championship: 3 }

  belongs_to :week
  belongs_to :home_college, class_name: "College"
  belongs_to :away_college, class_name: "College"
  has_many :college_game_stats, dependent: :destroy
  has_many :student_game_stats, dependent: :destroy
  has_many :injuries, dependent: :destroy
  belongs_to :offensive_player_of_game, class_name: "StudentSeason", optional: true
  belongs_to :defensive_player_of_game, class_name: "StudentSeason", optional: true
  has_many_attached :box_score_screenshots
  has_many_attached :home_stat_screenshots
  has_many_attached :away_stat_screenshots

  validate :home_and_away_colleges_differ
  validate :colleges_not_already_scheduled_this_week

  def played?
    college_game_stats.count == 2
  end

  private

  def home_and_away_colleges_differ
    return if home_college_id.blank? || away_college_id.blank?
    return if home_college_id != away_college_id

    errors.add(:away_college_id, "must be different from home college")
  end

  # A real team plays at most one game per week. Generic placeholder
  # opponents (conference "FCS", see colleges.rake) are exempt since one
  # college row there stands in for a different real team each time.
  def colleges_not_already_scheduled_this_week
    return if week_id.blank?

    [ [ :home_college_id, home_college ], [ :away_college_id, away_college ] ].each do |attribute, college|
      next if college.blank? || college.conference == "FCS"

      conflict = Game.where(week_id: week_id)
                      .where("home_college_id = :id OR away_college_id = :id", id: college.id)
                      .where.not(id: id)
                      .exists?
      errors.add(attribute, "#{college.name} already has a game scheduled for this week") if conflict
    end
  end
end
