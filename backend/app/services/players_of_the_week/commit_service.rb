module PlayersOfTheWeek
  # Persists a (possibly user-edited) set of Player of the Week groups for a
  # season. Same player-resolution approach as HeismanCandidates::CommitService:
  # Student.find_or_create_for_college scoped to the specific college, and
  # StudentSeason found-or-created without overwriting a real entry's
  # position/class_year. A college and a week are both required for every
  # row — there's no way to create/attach a Student without a college, and
  # no way to save an award without a week — so rows missing either are
  # reported as warnings instead of committed.
  #
  # Each row upserts by its slot (week, national, conference, side) via
  # find_or_initialize_by, so re-uploading a corrected screenshot updates
  # the existing record rather than duplicating it.
  class CommitService
    DEFAULT_CLASS_YEAR = "FR".freeze

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
        college_season = CollegeSeason.find_or_create_by!(college: college, season: @season)
        student = Student.find_or_create_for_college(first_name: row[:first_name], last_name: row[:last_name], college: college)
        student_season = StudentSeason.find_or_create_by!(student: student, college_season: college_season) do |ss|
          ss.position = row[:position]
          ss.class_year = row[:class_year].presence || DEFAULT_CLASS_YEAR
        end

        record = PlayerOfTheWeek.find_or_initialize_by(
          week: week, national: group[:national], conference: group[:conference], side: row[:side]
        )
        record.student_season = student_season
        record.stat_line = row[:stat_line]
        record.save!
      end
      nil
    end

    def player_label(row)
      "#{row[:first_name]} #{row[:last_name]}".strip
    end
  end
end
