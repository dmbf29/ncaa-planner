class Season < ApplicationRecord
  belongs_to :dynasty
  belongs_to :heisman, class_name: "StudentSeason", optional: true
  has_many :weeks, dependent: :destroy
  has_many :college_seasons, dependent: :destroy

  validates :year, presence: true, uniqueness: { scope: :dynasty }
  after_create_commit :setup_new_year

  def setup_new_year
    create_weeks
    create_college_seasons
  end

  def create_college_seasons
    College.find_each do |college|
      college_season = CollegeSeason.find_or_initialize_by(
        college:,
        season: self,
      )
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
