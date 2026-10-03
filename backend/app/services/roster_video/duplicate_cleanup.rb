module RosterVideo
  # Finds players that are on a roster TWICE (or on it under the wrong Student) when compared with a fresh
  # roster reading, and removes the extra row.
  #
  # A clip row that matches Student X has a "twin" when the same roster holds another row with the same
  # position, class and all seven ratings, a similar last name, and a Student (Y) that no clip row claims.
  # Two kinds, told apart by the first names:
  #   * typo duplicate  - Y's first name is compatible with the row's ("TJ Ulmenyiora" / "TJ Umenyiora", or a
  #                       lookalike-garbled "Moore Ill"): the same person written twice. One row survives.
  #   * wrong person    - Y's first name is not ("Amar Thomas" parked on "AJ Thomas"'s roster spot): Y's row on
  #                       this roster is removed; Y keeps the rest of their history.
  # Anything that would delete a record something else points to is reported for a human instead.
  class DuplicateCleanup
    Finding = Struct.new(:kind, :row, :matched_student_id, :drop, :manual_reason, keyword_init: true) do
      def describe
        "#{kind.to_s.tr('_', ' ')}: #{row[:first_name]} #{row[:last_name]} #{row[:position]} #{row[:class_year]} #{row[:overall]} also appears as " \
          "#{drop.student.name} (student #{drop.student_id}, #{drop.position} #{drop.class_year} #{drop.overall})"
      end
    end

    SIGNATURE = %i[overall speed acceleration agility change_of_direction strength awareness].freeze

    def initialize(college_season)
      @college_season = college_season
      @student_seasons = college_season.student_seasons.includes(:student).to_a
    end

    def call(rows)
      matched = rows.select { |row| row[:status] == "match" }.filter_map { |row| row[:student_id] }.to_set
      rows.select { |row| row[:status] == "match" }.filter_map { |row| finding_for(row, matched) }
    end

    def repair!(finding)
      raise "needs a human: #{finding.manual_reason}" if finding.manual_reason

      ActiveRecord::Base.transaction do
        finding.kind == :wrong_person ? drop_row!(finding.drop) : repair_typo_duplicate!(finding)
      end
    end

    private

    def finding_for(row, matched)
      twins = @student_seasons.select do |ss|
        ss.student_id != row[:student_id] && !matched.include?(ss.student_id) && same_signature?(ss, row) &&
          StringDistance.similar_name?(ss.student.last_name, row[:last_name])
      end
      return unless twins.size == 1

      twin = twins.first
      kind = RosterImport::Matcher.same_first_name?(twin.student.first_name, row[:first_name]) ? :typo_duplicate : :wrong_person
      Finding.new(kind: kind, row: row, matched_student_id: row[:student_id], drop: twin, manual_reason: manual_reason(kind, row, twin))
    end

    def manual_reason(kind, row, twin)
      return "#{twin.student.name} has signed-recruit records" if SignedRecruit.exists?(student_id: twin.student_id)
      return "game data points at #{twin.student.name}'s roster row" if referenced?(twin)
      return unless kind == :typo_duplicate

      kept = StudentSeason.find_by(college_season_id: @college_season.id, student_id: row[:student_id])
      other_history = ->(student_id, skip) { StudentSeason.where(student_id: student_id).where.not(id: skip).exists? }
      both = other_history.call(twin.student_id, twin.id) && other_history.call(row[:student_id], kept&.id)
      "both #{twin.student.name} and the matched Student have their own history" if both
    end

    def repair_typo_duplicate!(finding)
      row = finding.row
      twin = finding.drop
      kept = StudentSeason.find_by(college_season_id: @college_season.id, student_id: finding.matched_student_id)
      twin_has_history = StudentSeason.where(student_id: twin.student_id).where.not(id: twin.id).exists?

      if kept.nil?
        # The matched Student isn't on this roster yet: hand them the existing row instead of adding a second.
        twin.update!(student_id: finding.matched_student_id)
        delete_if_orphan!(twin.student_id_before_last_save)
      elsif twin_has_history
        # The twin's Student carries the real history: keep them (spelled correctly) and drop the other row.
        survivor = twin.student
        drop = kept
        survivor.update!(first_name: row[:first_name], last_name: row[:last_name])
        drop_row!(drop)
      else
        drop_row!(twin)
      end
    end

    def drop_row!(student_season)
      raise "needs a human: game data points at #{student_season.student.name}'s roster row" if referenced?(student_season)

      student_id = student_season.student_id
      student_season.destroy!
      delete_if_orphan!(student_id)
    end

    def delete_if_orphan!(student_id)
      student = Student.find_by(id: student_id)
      student&.destroy! if student && !student.student_seasons.exists? && !SignedRecruit.exists?(student_id: student_id)
    end

    def same_signature?(student_season, row)
      PositionBoardMapping.canonical(student_season.position) == PositionBoardMapping.canonical(row[:position]) &&
        student_season.class_year == row[:class_year] &&
        SIGNATURE.all? { |key| row[key].present? && student_season[key] == row[key].to_i }
    end

    # Does any table hold a student_season_id pointing at this row? Deleting it would orphan that data.
    def referenced?(student_season)
      connection = ActiveRecord::Base.connection
      connection.tables.any? do |table|
        connection.columns(table).any? { |column| column.name == "student_season_id" } &&
          connection.select_value("SELECT 1 FROM #{connection.quote_table_name(table)} WHERE student_season_id = #{student_season.id.to_i} LIMIT 1")
      end
    end
  end
end
