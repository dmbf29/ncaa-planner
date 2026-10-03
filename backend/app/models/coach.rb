class Coach < ApplicationRecord
  belongs_to :dynasty
  has_many :college_seasons, dependent: :nullify
  has_many :season_awards, dependent: :destroy

  validates :name, presence: true
  validates :job_security, numericality: { only_integer: true, in: 0..100 }, allow_nil: true

  # The coach's job-security percentage (entered by hand from the game) bucketed
  # into the same labels the game shows.
  def job_security_label
    return nil if job_security.nil?

    case job_security
    when 80.. then "Safe"
    when 65..79 then "Safe for Now"
    when 50..64 then "Low"
    else "Hot Seat"
    end
  end

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
