module RosterImport
  # Resolves one imported roster row to a Student — or flags it as
  # ambiguous rather than silently guessing. Checked in up to two pools:
  # first this *same* CollegeSeason (a same-season refresh should update
  # the same players, not duplicate them), then the *previous* season's
  # roster for this college, constrained by CLASS_YEAR_PREDECESSORS so a
  # same-name-and-initial collision from a *different* player doesn't pull
  # in the wrong one now that most colleges have their full roster seeded.
  #
  # The pasted first_name is only a first initial (e.g. "N"), never a full
  # first name, so matching compares last_name exactly and only the first
  # character of first_name — never full first-name equality.
  class Matcher
    # A redshirt can only happen once in a career, so a plain (non-RS) class
    # year proves it hasn't happened yet and has exactly one possible
    # predecessor. An (RS) class year has two possible predecessors: either
    # they were already tagged (redshirt happened earlier, this is just
    # normal progression) or this is the transition where the redshirt was
    # just taken (previous season is the plain version of the same tier).
    # "FR" has no entry — a true freshman is always a new Student, never
    # matched against a previous season.
    CLASS_YEAR_PREDECESSORS = {
      "FR(RS)" => %w[FR],
      "SO" => %w[FR],
      "SO(RS)" => %w[FR(RS) SO],
      "JR" => %w[SO],
      "JR(RS)" => %w[SO(RS) JR],
      "SR" => %w[JR],
      "SR(RS)" => %w[JR(RS) SR]
    }.freeze

    # The imported class years use a space before the redshirt suffix
    # ("JR (RS)") but the rest of the app stores it without one ("JR(RS)") —
    # see CollegeSeason::CLASS_BUCKETS / UNDERCLASS_YEARS.
    def self.normalize_class_year(class_year)
      class_year.to_s.strip.sub(/\s+\(RS\)/, "(RS)")
    end

    def initialize(college_season)
      @college_season = college_season
      @current_student_seasons = @college_season.student_seasons.includes(:student).to_a
      @previous_student_seasons = previous_student_seasons
    end

    # row must already have a normalized :class_year. Returns one of:
    #   { status: "new" }
    #   { status: "match", student_id:, matched_name: }
    #   { status: "ambiguous", suggested_student_id:, candidates: [...] }
    def resolve(row)
      current_candidates = name_candidates(@current_student_seasons, row, class_years: nil)
      return build_result(current_candidates, row) if current_candidates.any?

      previous_candidates = name_candidates(
        @previous_student_seasons, row, class_years: CLASS_YEAR_PREDECESSORS.fetch(row[:class_year], [])
      )
      build_result(previous_candidates, row)
    end

    private

    def build_result(candidates, row)
      case candidates.size
      when 0
        { status: "new" }
      when 1
        { status: "match", student_id: candidates.first.student_id, matched_name: candidates.first.student.name }
      else
        suggested = candidates.find { |ss| ss.position == row[:position] } || candidates.first
        {
          status: "ambiguous",
          suggested_student_id: suggested.student_id,
          candidates: candidates.map { |ss| candidate_json(ss) }
        }
      end
    end

    def name_candidates(pool, row, class_years:)
      return [] if pool.empty? || class_years == []

      initial = row[:first_name].to_s.strip[0]&.downcase
      last = row[:last_name].to_s.strip.downcase
      pool.select do |ss|
        ss.student.last_name.to_s.strip.downcase == last &&
          ss.student.first_name.to_s.strip[0]&.downcase == initial &&
          (class_years.nil? || class_years.include?(ss.class_year))
      end
    end

    def candidate_json(student_season)
      {
        student_id: student_season.student_id,
        name: student_season.student.name,
        position: student_season.position,
        class_year: student_season.class_year,
        overall: student_season.overall
      }
    end

    def previous_student_seasons
      previous_season = @college_season.season.previous_season
      return [] unless previous_season

      previous_college_season = previous_season.college_seasons.find_by(college_id: @college_season.college_id)
      return [] unless previous_college_season

      previous_college_season.student_seasons.includes(:student).to_a
    end
  end
end
