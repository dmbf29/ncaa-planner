module PlayersOfTheWeek
  # Persists a (possibly user-edited) set of Player of the Week groups for a
  # season. Never creates players: rosters are imported at the start of the
  # season, so each row must match a student already on that college's
  # roster for the season (names compared via Student.match_key). A row with
  # no match is reported as a warning rather than creating a stray student.
  # A college and a week are both required for every row, so rows missing
  # either are reported as warnings instead of committed.
  #
  # Each row upserts by its slot (week, national, conference, side) via
  # find_or_initialize_by, so re-uploading a corrected screenshot updates
  # the existing record rather than duplicating it.
  class CommitService
    def initialize(season)
      @season = season
    end

    def call(groups)
      Array(groups).flat_map { |group| commit_group(group.deep_symbolize_keys) }
    end

    private

    def commit_group(group)
      week = @season.weeks.find_by(id: group[:week_id])

      Array(group[:rows]).filter_map do |raw_row|
        row = raw_row.deep_symbolize_keys
        next { player: player_label(row), error: "week is required" } if week.blank?
        next { player: player_label(row), error: "college is required" } if row[:college_id].blank?

        commit_row(group, week, row)
        nil
      rescue ActiveRecord::RecordInvalid => e
        { player: player_label(row), error: e.message }
      end
    end

    def commit_row(group, week, row)
      college = College.find_by(id: row[:college_id])
      return if college.blank? || row[:first_name].blank? || row[:last_name].blank?

      ActiveRecord::Base.transaction do
        student_season = find_student_season(college, row)
        next { player: player_label(row), error: "not on #{college.name}'s roster this season" } if student_season.blank?

        record = PlayerOfTheWeek.find_or_initialize_by(
          week: week, national: group[:national], conference: group[:conference], side: row[:side]
        )
        record.student_season = student_season
        record.stat_line = row[:stat_line]
        record.save!
        nil
      end
    end

    def find_student_season(college, row)
      key = Student.match_key("#{row[:first_name]} #{row[:last_name]}")
      @season.college_seasons.find_by(college: college)
             &.student_seasons&.includes(:student)
             &.find { |ss| Student.match_key(ss.student.name) == key }
    end

    def player_label(row)
      "#{row[:first_name]} #{row[:last_name]}".strip
    end
  end
end
