class PlayerOfTheWeek < ApplicationRecord
  # Rails' inflector would otherwise expect table "player_of_the_weeks"
  # (pluralizing "week", the last word) — pin it to the more natural
  # "players_of_the_week" the migration actually created.
  self.table_name = "players_of_the_week"

  SIDES = %w[offensive defensive].freeze

  belongs_to :week
  belongs_to :student_season

  validates :side, inclusion: { in: SIDES }
  validates :conference, presence: true, unless: :national
  validates :conference, absence: true, if: :national
  validates :week, uniqueness: { scope: %i[national conference side], message: "already has a player of the week for this slot" }
end
