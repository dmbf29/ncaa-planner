module HeismanCandidates
  # Persists a (possibly user-edited) week's Heisman Watch List. Order
  # doesn't matter — it's just the set of that week's candidates — so each
  # row only needs to resolve/create its player and record them against
  # the week, once.
  #
  # Same player-resolution approach as AllAmericans::CommitService:
  # Student.find_or_create_for_college scoped to the specific college
  # (never a global name search, per the AllAmericans discussion) and
  # StudentSeason found-or-created without overwriting a real scraped
  # entry's position/class_year. CollegeSeason is found-or-created rather
  # than assumed to exist, for the same reason as ScheduleStats/
  # AllAmericans: a freshly-started season won't have one yet for anything
  # but the coached teams.
  #
  # Each row commits in its own transaction and a validation failure is
  # caught and reported as a warning rather than aborting the rest of the
  # batch, mirroring the other CommitServices.
  class CommitService
    def initialize(week)
      @week = week
      @season = week.season
    end

    def call(rows)
      Array(rows).filter_map do |row|
        symbolized = row.deep_symbolize_keys
        commit_row(symbolized)
        nil
      rescue ActiveRecord::RecordInvalid => e
        { player: "#{symbolized[:first_name]} #{symbolized[:last_name]}".strip, error: e.message }
      end
    end

    private

    def commit_row(row)
      college = College.find_by(id: row[:college_id])
      return if college.blank? || row[:first_name].blank? || row[:last_name].blank?

      ActiveRecord::Base.transaction do
        college_season = CollegeSeason.find_or_create_by!(college: college, season: @season)
        student = Student.find_or_create_for_college(first_name: row[:first_name], last_name: row[:last_name], college: college)
        student_season = StudentSeason.find_or_create_by!(student: student, college_season: college_season) do |ss|
          ss.position = row[:position]
          ss.class_year = row[:class_year]
        end

        HeismanCandidate.find_or_create_by!(week: @week, student_season: student_season)
      end
    end
  end
end
