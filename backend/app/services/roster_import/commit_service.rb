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
    end

    def call(players)
      warnings = Array(players).filter_map { |row| commit_row(row.deep_symbolize_keys) }
      link_history
      warnings
    end

    private

    # Matching checks this season's roster first, so a player created earlier
    # this season by another upload (e.g. the All-Americans) is updated in
    # place and never looked up in last season. HistoryLinker reconnects them
    # to their real Student afterwards. The rows are already committed, so a
    # failure here is logged rather than failing the import.
    def link_history
      HistoryLinker.new(@college_season).call
    rescue StandardError => e
      Rails.logger.warn("RosterImport history link failed for college_season #{@college_season.id}: #{e.message}")
    end

    def commit_row(row)
      student = row[:student_id].present? ? Student.find(row[:student_id]) : create_student(row)
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
      nil
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
      { player: "#{row[:first_name]} #{row[:last_name]}".strip, error: e.message }
    end

    def create_student(row)
      Student.create!(first_name: row[:first_name], last_name: row[:last_name])
    end
  end
end
