class Coach < ApplicationRecord
  belongs_to :dynasty
  has_many :college_seasons, dependent: :nullify
  has_many :season_awards, dependent: :destroy

  validates :name, presence: true

  # Name is unique per dynasty, case-insensitively (see the matching DB
  # index). Award commits use this to attach a winner to an existing CPU
  # coach or spin one up on first mention without ever creating a casing
  # duplicate.
  def self.find_or_create_for_dynasty!(dynasty:, name:)
    normalized = name.to_s.strip
    dynasty.coaches.where("lower(name) = ?", normalized.downcase).first ||
      dynasty.coaches.create!(name: normalized)
  end
end
