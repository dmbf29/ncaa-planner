class Season < ApplicationRecord
  belongs_to :dynasty
  has_many :weeks, dependent: :destroy
  has_many :college_seasons, dependent: :destroy
  has_many :season_awards, dependent: :destroy
  has_many :awards, through: :season_awards

  validates :year, presence: true, uniqueness: { scope: :dynasty }
  after_create_commit :setup_new_year

  def setup_new_year
    create_weeks
    create_college_seasons
  end

  # The StudentSeason that won the Heisman this season, if one has been
  # recorded. Kept as a named helper because the dashboard/broadcast code
  # calls it directly the way it used to read the old `heisman` association.
  def heisman_winner
    season_awards.joins(:award).find_by(awards: { name: "Heisman Trophy" })&.student_season
  end

  def previous_season
    dynasty.seasons.where("year < ?", year).order(year: :desc).first
  end

  def create_college_seasons
    previous_conferences = previous_season&.college_seasons&.pluck(:college_id, :conference)&.to_h || {}

    College.find_each do |college|
      college_season = CollegeSeason.find_or_initialize_by(
        college:,
        season: self,
      )
      college_season.conference ||= previous_conferences[college.id] || college.conference
      college_season.save
    end
  end

  def create_weeks
    (0..14).each do |number|
      Week.create(season: self, number:)
    end
    Week.create(season: self, number: 15, conference_championship: true)
    Week.create(season: self, number: 16, post_season: true, name: "Bowl Week 1")
    Week.create(season: self, number: 17, post_season: true, name: "Bowl Week 2")
    Week.create(season: self, number: 18, post_season: true, name: "Bowl Week 3")
    Week.create(season: self, number: 19, post_season: true, name: "Bowl Week 4")
  end
  # 0-14
  # 15 cc
  # 16 bowl 1
  # 17 bowl 2
  # 18 bowl 3
  # 19 bowl 4
end
