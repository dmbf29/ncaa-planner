module RosterImport
  # Bulk-applies a pasted roster snapshot (typically copied a position group
  # at a time from the game's roster screen) onto a single CollegeSeason.
  #
  # Every row is matched against an existing Student, checked in up to two
  # places: first this *same* CollegeSeason (so re-importing a fresher/
  # corrected snapshot of the current season updates the same players
  # instead of duplicating them), then — unless the row is a true freshman
  # ("FR"), who by definition can't have played last year — the *previous*
  # season's roster for this college (so the same real player keeps one
  # Student record across a season transition). If nothing matches, they're
  # a new Student (an incoming true freshman or transfer).
  #
  # The pasted first_name is only a first initial (e.g. "N"), never a full
  # first name, so matching compares last_name exactly and only the first
  # character of first_name — never full first-name equality.
  #
  # Each row commits independently; a validation failure is reported as a
  # warning rather than aborting the rest of the paste, mirroring the other
  # CommitServices. No removal of players missing from the import — this is
  # additive/upsert only, since a pasted screen is typically a partial roster.
  class CommitService
    def initialize(college_season)
      @college_season = college_season
      @current_student_seasons = @college_season.student_seasons.includes(:student).to_a
      @previous_student_seasons = previous_student_seasons
    end

    def call(players)
      Array(players).filter_map { |row| commit_row(row.deep_symbolize_keys) }
    end

    private

    def commit_row(row)
      student = find_or_create_student(row)
      student_season = student.student_seasons.find_or_initialize_by(college_season: @college_season)
      student_season.class_year = normalize_class_year(row[:class_year])
      student_season.position = row[:position]
      student_season.overall = row[:overall].presence&.to_i
      student_season.nil_amount = row[:nil_amount].presence&.to_i
      student_season.speed = row[:speed].presence&.to_i
      student_season.save!
      nil
    rescue ActiveRecord::RecordInvalid => e
      { player: "#{row[:first_name]} #{row[:last_name]}".strip, error: e.message }
    end

    # "FR" always skips the *previous*-season check (a true freshman can't
    # have played last year) but still checks the *current* season first —
    # a same-season refresh/correction import can easily already contain
    # them from an earlier import.
    def find_or_create_student(row)
      matching_student(@current_student_seasons, row) ||
        (row[:class_year].to_s.strip.upcase == "FR" ? nil : matching_student(@previous_student_seasons, row)) ||
        create_student(row)
    end

    def create_student(row)
      Student.create!(first_name: row[:first_name], last_name: row[:last_name])
    end

    def matching_student(pool, row)
      initial = row[:first_name].to_s.strip[0]&.downcase
      last = row[:last_name].to_s.strip.downcase
      candidates = pool.select do |ss|
        ss.student.last_name.to_s.strip.downcase == last &&
          ss.student.first_name.to_s.strip[0]&.downcase == initial
      end
      return nil if candidates.empty?
      return candidates.first.student if candidates.size == 1

      (candidates.find { |ss| ss.position == row[:position] } || candidates.first).student
    end

    def previous_student_seasons
      previous_season = @college_season.season.previous_season
      return [] unless previous_season

      previous_college_season = previous_season.college_seasons.find_by(college_id: @college_season.college_id)
      return [] unless previous_college_season

      previous_college_season.student_seasons.includes(:student).to_a
    end

    # The imported class years use a space before the redshirt suffix
    # ("JR (RS)") but the rest of the app stores it without one ("JR(RS)") —
    # see CollegeSeason::CLASS_BUCKETS / UNDERCLASS_YEARS.
    def normalize_class_year(class_year)
      class_year.to_s.strip.sub(/\s+\(RS\)/, "(RS)")
    end
  end
end
