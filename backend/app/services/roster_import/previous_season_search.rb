module RosterImport
  # Manual fallback for when the automatic matcher wrongly treats a
  # returning player as new — usually because the stored name doesn't
  # split the way the pasted row's name does (e.g. a compound surname with
  # no recognizable particle, like "Diaz Nicolas"). Lets the user search
  # the whole previous season by name and pick the real match themselves,
  # with no class-year-progression filter: the point of a manual search is
  # precisely that the automatic rules already missed this one, so the
  # human should get the final call rather than the same rules filtering
  # the search results too.
  class PreviousSeasonSearch
    MIN_QUERY_LENGTH = 2
    MAX_RESULTS = 25

    def initialize(college_season)
      @college_season = college_season
    end

    def call(query)
      query = query.to_s.strip
      return [] if query.length < MIN_QUERY_LENGTH

      previous_season = @college_season.season.previous_season
      return [] unless previous_season

      needle = query.downcase
      previous_season.student_seasons
                      .includes(:student, college_season: :college)
                      .to_a
                      .select { |ss| ss.student.name.downcase.include?(needle) }
                      .first(MAX_RESULTS)
                      .map { |ss| candidate_json(ss) }
    end

    private

    def candidate_json(student_season)
      {
        student_id: student_season.student_id,
        name: student_season.student.name,
        college: student_season.college_season.college.name,
        position: student_season.position,
        class_year: student_season.class_year,
        overall: student_season.overall
      }
    end
  end
end
