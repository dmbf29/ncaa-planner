class Game < ApplicationRecord
  belongs_to :week
  belongs_to :home_college, class_name: "College"
  belongs_to :away_college, class_name: "College"
  has_many :college_game_stats, dependent: :destroy
  has_many :student_game_stats, dependent: :destroy

  validate :home_and_away_colleges_differ

  private

  def home_and_away_colleges_differ
    return if home_college_id.blank? || away_college_id.blank?
    return if home_college_id != away_college_id

    errors.add(:away_college_id, "must be different from home college")
  end
end
