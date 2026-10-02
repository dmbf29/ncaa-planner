module RosterImport
  # Applies a roster snapshot that's already been through Analyzer and
  # reviewed by the user — each row carries the student_id it should
  # attach to (nil for "create a new Student"), so this service does no
  # matching/guessing of its own, only persistence.
  #
  # Each row commits independently; a validation failure is reported as a
  # warning rather than aborting the rest of the batch, mirroring the other
  # CommitServices. No removal of players missing from the import — this is
  # additive/upsert only, since a pasted screen is typically a partial roster.
  # Afterwards, players with no history are linked to last season (see
  # HistoryLinker).
  class CommitService
    def initialize(college_season)
      @college_season = college_season
      @claimed_student_ids = Set.new
    end

    def call(players)
      warnings = Array(players).filter_map { |row| commit_row(Matcher.normalize_keys(row.deep_symbolize_keys)) }
      link_history
      warnings
    end

    private

    # Matching above checks this season's roster first, so a player created
    # earlier this season by another upload (e.g. the All-Americans) is
    # updated in place and never looked up in last season. HistoryLinker
    # reconnects them to their real Student afterwards. The rows are already
    # committed, so a failure here is logged rather than failing the import.
    def link_history
      HistoryLinker.new(@college_season).call
    rescue StandardError => e
      Rails.logger.warn("RosterImport history link failed for college_season #{@college_season.id}: #{e.message}")
    end

    def commit_row(row)
      student = Student.find(row[:student_id]) if row[:student_id].present?
      if student && (conflict = conflict_message(student))
        return { player: "#{row[:first_name]} #{row[:last_name]}".strip, error: conflict }
      end

      student ||= create_student(row)
      student_season = student.student_seasons.find_or_initialize_by(college_season: @college_season)
      student_season.class_year = Matcher.normalize_class_year(row[:class_year])
      student_season.position = row[:position]
      student_season.overall = row[:overall].presence&.to_i
      student_season.nil_amount = row[:nil_amount].presence&.to_i
      student_season.speed = row[:speed].presence&.to_i
      student_season.acceleration = row[:acceleration].presence&.to_i
      student_season.agility = row[:agility].presence&.to_i
      student_season.change_of_direction = row[:change_of_direction].presence&.to_i
      student_season.strength = row[:strength].presence&.to_i
      student_season.awareness = row[:awareness].presence&.to_i
      student_season.save!
      @claimed_student_ids << student.id
      nil
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ActiveRecord::RecordNotUnique => e
      { player: "#{row[:first_name]} #{row[:last_name]}".strip, error: e.message }
    end

    # A student gets one StudentSeason per season: reject a row that would
    # attach them a second time — either to another row in this same batch
    # (two rows resolved to the same student, which would silently overwrite
    # each other) or to a different college's roster already this season.
    def conflict_message(student)
      return "Already matched to another row in this import" if @claimed_student_ids.include?(student.id)

      elsewhere = student.student_seasons
                         .joins(:college_season)
                         .where(college_seasons: { season_id: @college_season.season_id })
                         .where.not(college_season_id: @college_season.id)
                         .includes(college_season: :college)
                         .first
      return unless elsewhere

      "Already on #{elsewhere.college_season.college.name}'s #{@college_season.season.year} roster"
    end

    def create_student(row)
      Student.create!(first_name: row[:first_name], last_name: row[:last_name])
    end
  end
end
