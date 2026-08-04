module GameStats
  module Roster
    module_function

    # Returns [{ id:, name:, position: }] for a college's roster in the given
    # season, or [] if that college has no scraped roster (e.g. an opponent
    # we don't coach).
    def for(college, season)
      college_season = CollegeSeason.find_by(college: college, season: season)
      return [] unless college_season

      college_season.student_seasons.includes(:student).map do |student_season|
        { id: student_season.id, name: student_season.student.name, position: student_season.position }
      end
    end
  end
end
