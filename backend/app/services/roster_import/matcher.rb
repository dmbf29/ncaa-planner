module RosterImport
  # Resolves one imported roster row to a Student — or flags it as
  # ambiguous rather than silently guessing. Checked in up to two pools:
  # first this *same* CollegeSeason (a same-season refresh should update
  # the same players, not duplicate them), then the *previous* season
  # *league-wide* (every college, not just this one), constrained by
  # CLASS_YEAR_PREDECESSORS — a returning player who stayed and a transfer
  # who switched schools both show up as "last season, somewhere, with a
  # class year that legitimately progresses into this row's" and are
  # handled identically. Searching the whole league (not just this college)
  # is what makes transfers resolve to their real Student instead of being
  # created as a duplicate "new" one every time they switch teams.
  #
  # Positions are compared via PositionBoardMapping.canonical: the first season's
  # rosters were scraped with older codes (MLB, LE, RE, LOLB, ROLB) while the game
  # and later imports use MIKE, LEDG, REDG, SAM, WILL — same position, different code.
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

    # See #same_first_name?
    def self.same_first_name?(existing, incoming)
      a = existing.to_s.strip.downcase
      b = incoming.to_s.strip.downcase
      return a[0] == b[0] if a.length < 2 || b.length < 2

      StringDistance.levenshtein(a, b) <= (a.length >= 8 && b.length >= 8 ? 2 : 1)
    end

    # The imported class years use a space before the redshirt suffix
    # ("JR (RS)") but the rest of the app stores it without one ("JR(RS)") —
    # see CollegeSeason::CLASS_BUCKETS / UNDERCLASS_YEARS.
    def self.normalize_class_year(class_year)
      class_year.to_s.strip.upcase.sub(/\s+\(RS\)/, "(RS)")
    end

    # The pasted JSON comes from an external export whose key spelling has
    # drifted before ("first name" instead of "first_name"), and a missing
    # first_name silently turns every row into a "new" player — so keys are
    # forced to snake_case ("first name", "first-name" -> first_name).
    def self.normalize_keys(row)
      row.transform_keys { |key| key.to_s.strip.downcase.gsub(/[\s-]+/, "_").to_sym }
    end

    def initialize(college_season)
      @college_season = college_season
      @current_student_seasons = @college_season.student_seasons.includes(:student).to_a
      @previous_student_seasons = previous_student_seasons
      @previous_signed_recruits = previous_signed_recruits
    end

    # row must already have a normalized :class_year. Returns one of:
    #   { status: "new" }
    #   { status: "new", suggested_first_name:, suggested_last_name: }  (name pulled from a signed HS recruit)
    #   { status: "match", student_id:, matched_name:, matched_college: }
    #   { status: "ambiguous", suggested_student_id:, candidates: [...] }
    def resolve(row)
      current_candidates = name_candidates(@current_student_seasons, row, class_years: nil)
      return build_result(current_candidates, row) if current_candidates.any?

      previous_candidates = name_candidates(
        @previous_student_seasons, row, class_years: CLASS_YEAR_PREDECESSORS.fetch(row[:class_year], [])
      )
      result = build_result(previous_candidates, row)
      return result unless result[:status] == "new" && row[:class_year] == "FR"

      recruit = matching_signed_recruit(row)
      return result unless recruit

      { status: "new", suggested_first_name: recruit.first_name, suggested_last_name: recruit.last_name }
    end

    private

    def build_result(candidates, row)
      candidates = narrow_by_full_first_name(candidates, row)
      case candidates.size
      when 0
        { status: "new" }
      when 1
        matched = candidates.first
        { status: "match", student_id: matched.student_id, matched_name: matched.student.name,
          matched_college: matched.college_season.college.name }
      else
        position = PositionBoardMapping.canonical(row[:position])
        suggested = candidates.find { |ss| PositionBoardMapping.canonical(ss.position) == position } || candidates.first
        {
          status: "ambiguous",
          suggested_student_id: suggested.student_id,
          candidates: candidates.map { |ss| candidate_json(ss) }
        }
      end
    end

    def name_candidates(pool, row, class_years:)
      return [] if pool.empty? || class_years == []

      last = row[:last_name].to_s.strip.downcase
      pool.select do |ss|
        ss.student.last_name.to_s.strip.downcase == last &&
          same_first_name?(ss.student.first_name, row[:first_name]) &&
          (class_years.nil? || class_years.include?(ss.class_year))
      end
    end

    # An initial on either side (the old paste format, or a Student never given a
    # full name) can only be compared by that initial. When both are full names they
    # must agree, give or take one OCR slip ("Tawfio"/"Tawfiq", from the roster-video
    # tool) — otherwise "Rayshon Gold" would match "Ramon Gold" just because both
    # start with R, merging two different players. A true nickname difference
    # ("Mike"/"Michael") comes through as a new player; the review screen's manual
    # match search is the way to link it.
    def same_first_name?(existing, incoming)
      self.class.same_first_name?(existing, incoming)
    end

    # Rows can now carry a full first name (e.g. from the roster-video
    # tool), which tells apart two players who share an initial and last name
    # ("Marcus Smith" / "Michael Smith"). Only ever narrows: if no candidate's
    # full first name agrees (an OCR slip, a nickname) the list is left alone,
    # so a bad full name can't turn a real match into a duplicate "new" player.
    def narrow_by_full_first_name(candidates, row)
      return candidates if candidates.size < 2

      first = row[:first_name].to_s.strip.downcase
      return candidates if first.length < 2

      exact = candidates.select { |ss| ss.student.first_name.to_s.strip.downcase == first }
      exact.any? ? exact : candidates
    end

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

    def previous_student_seasons
      previous_season = @college_season.season.previous_season
      return [] unless previous_season

      previous_season.student_seasons.includes(:student, college_season: :college).to_a
    end

    # Unlike transfers, a true freshman only ever signed with one program —
    # so this is scoped to this same college's previous-season signing
    # class, not league-wide. Only non-transfer, high-school-or-unspecified
    # signees count (a JUCO signee arrives with standing, not as "FR"), and
    # only ones where the reviewer has actually typed in a full first name
    # (SignedRecruit#first_name starts blank — RecruitmentTrail::Extractor
    # only ever reads a first initial off the recruiting screen, same as
    # this importer's own source data, so a blank one has nothing to offer).
    def previous_signed_recruits
      previous_season = @college_season.season.previous_season
      return [] unless previous_season

      previous_college_season = previous_season.college_seasons.find_by(college_id: @college_season.college_id)
      return [] unless previous_college_season

      previous_college_season.signed_recruits
                              .where(transfer: false)
                              .select { |r| r.first_name.present? && r.class_year.to_s.strip.upcase.in?([ "", "HS" ]) }
    end

    # Only suggested when exactly one signee matches — unlike the Student
    # pools above, an ambiguous recruit match isn't worth a review-screen
    # picker (there's no Student to link to either way, just a name to
    # pre-fill), so a genuine collision here just falls back to the bare
    # initial the same as if no recruit record existed at all.
    def matching_signed_recruit(row)
      last = row[:last_name].to_s.strip.downcase
      candidates = @previous_signed_recruits.select do |recruit|
        recruit.last_name.to_s.strip.downcase == last && same_first_name?(recruit.first_name, row[:first_name])
      end
      candidates.first if candidates.size == 1
    end
  end
end
