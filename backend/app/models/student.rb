class Student < ApplicationRecord
  has_many :student_seasons, dependent: :destroy

  validates :first_name, presence: true
  validates :last_name, presence: true

  def name
    "#{first_name} #{last_name}".strip
  end

  # Matching by name alone risks merging two different real people who
  # happen to share a name at different colleges, so reuse is scoped to
  # "does this college already have a student_season for this name" (any
  # season, so identity survives across a player's career at one college)
  # rather than a global name search.
  #
  # Matches on the full concatenated name rather than first_name/last_name
  # individually, since where the name gets split can legitimately differ
  # between data sources — e.g. ScrapeStudentsJob's naive "last word is the
  # last name" split turns "Carlos Del Rio-Wilson" into ("Carlos Del",
  # "Rio-Wilson"), while an LLM asked to split the same string naturally
  # returns ("Carlos", "Del Rio-Wilson"). Both are the same real person.
  def self.find_or_create_for_college(first_name:, last_name:, college:)
    full_name = "#{first_name} #{last_name}".strip

    existing = joins(student_seasons: :college_season)
               .where(college_seasons: { college_id: college.id })
               .distinct
               .find { |student| student.name.casecmp?(full_name) }
    existing || create!(first_name: first_name, last_name: last_name)
  end
end
