module RosterVideo
  # Finds players already on a roster that are attached to the WRONG Student, using
  # a fresh roster reading (e.g. a video) as the reference.
  #
  # The old importer matched on last name + first *initial* only, so "Trevor
  # Calloway" got linked to an unrelated "Trace Calloway" from last season. With
  # full first names the matcher now refuses that link, so the row comes back as a
  # "new" player — but the roster already has a row for them under the wrong name.
  # A row is reported when the roster has exactly one existing player with the same
  # last name, position, class and ALL seven ratings but a different first name:
  # that is the same person, and the existing row's Student is the wrong one.
  #
  # Writing the "new" row as-is would duplicate the player, so callers should
  # leave findings out of their commit. repair! gives the existing row a new
  # Student with the correct name (the old Student keeps their real history), or
  # simply fixes the spelling when the old Student has no history of their own.
  class LinkAudit
    STAT_KEYS = %i[overall speed acceleration agility change_of_direction strength awareness].freeze

    Finding = Struct.new(:row, :student_season, :history, :repairable, keyword_init: true) do
      def describe
        "#{row[:first_name]} #{row[:last_name]} #{row[:position]} #{row[:class_year]} is stored as #{student_season.student.name} " \
          "(student #{student_season.student_id}), whose real history is #{history.presence&.join(', ') || 'none'}"
      end
    end

    def initialize(college_season)
      @student_seasons = college_season.student_seasons.includes(:student).to_a
    end

    # rows: Analyzer output (symbol keys, normalized class_year). Returns [Finding].
    def call(rows)
      matched = rows.select { |row| row[:status] == "match" }.filter_map { |row| row[:student_id] }.to_set
      rows.select { |row| row[:status] == "new" }.filter_map { |row| finding_for(row, matched) }
    end

    def repair!(finding)
      raise "refusing to repair: #{finding.student_season.student.name} has signed-recruit records" unless finding.repairable
      raise "refusing to repair: the new name #{finding.row[:last_name].inspect} still looks garbled" if StringDistance.garbled_name?(finding.row[:last_name])

      ActiveRecord::Base.transaction do
        # No other history: it is the right person with a misspelt name ("Tretn"), so correct the name rather than
        # leaving an orphaned Student behind. Otherwise it is a different person's record: give this row its own Student.
        if finding.history.empty?
          student = finding.student_season.student
          student.update!(first_name: finding.row[:first_name], last_name: finding.row[:last_name])
          student
        else
          fresh = Student.create!(first_name: finding.row[:first_name], last_name: finding.row[:last_name])
          finding.student_season.update!(student_id: fresh.id)
          fresh
        end
      end
    end

    private

    def finding_for(row, matched_student_ids)
      candidates = @student_seasons.select do |ss|
        !matched_student_ids.include?(ss.student_id) && same_player?(ss, row)
      end
      return unless candidates.size == 1

      ss = candidates.first
      history = ss.student.student_seasons.where.not(id: ss.id).includes(college_season: %i[college season]).map do |other|
        "#{other.college_season.season.year} #{other.college_season.college.name} #{other.position} #{other.class_year} #{other.overall}"
      end
      Finding.new(row: row, student_season: ss, history: history, repairable: !SignedRecruit.exists?(student_id: ss.student_id))
    end

    def same_player?(student_season, row)
      StringDistance.similar_name?(student_season.student.last_name, row[:last_name]) &&
        PositionBoardMapping.canonical(student_season.position) == PositionBoardMapping.canonical(row[:position]) &&
        student_season.class_year == row[:class_year] &&
        STAT_KEYS.all? { |key| row[key].present? && student_season[key] == row[key].to_i }
    end
  end
end
