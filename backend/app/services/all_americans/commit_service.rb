module AllAmericans
  # Persists a (possibly user-edited) set of All-American groups for one
  # season. For each player row: resolves (or creates) the Student via
  # Student.find_or_create_for_college — scoped to the specific college so
  # a name match doesn't accidentally merge two different real people who
  # share a name at different schools — then finds-or-creates their
  # StudentSeason (only setting position/class_year when actually creating
  # a new one, so a real scraped roster entry's data is never overwritten
  # by what this screenshot shows), then upserts the AllAmerican honor
  # itself, keyed on (student_season, national, conference, preseason) with
  # tier refreshed in place — so re-uploading a corrected screenshot (e.g.
  # a player moved from 2nd team to 1st) fixes the existing row rather than
  # duplicating it.
  #
  # CollegeSeason is found-or-created rather than assumed to exist, since a
  # freshly-started season won't have one yet for anything but the coached
  # teams (only "dynasty:create" backfills every college, and that's a
  # one-time setup script, not something that reruns per season) — and
  # preseason All-Americans are exactly the kind of upload that happens
  # right after a new season is created.
  #
  # Each row commits in its own transaction and a validation failure is
  # caught and reported as a warning rather than aborting the rest of the
  # batch, mirroring RankingStats::CommitService / ScheduleStats::CommitService.
  class CommitService
    def initialize(season)
      @season = season
    end

    def call(groups)
      Array(groups).flat_map do |group|
        commit_group(group.deep_symbolize_keys)
      end
    end

    private

    def commit_group(group)
      Array(group[:rows]).filter_map do |row|
        commit_row(group, row)
        nil
      rescue ActiveRecord::RecordInvalid => e
        { player: "#{row[:first_name]} #{row[:last_name]}".strip, error: e.message }
      end
    end

    def commit_row(group, row)
      college = College.find_by(id: row[:college_id])
      return if college.blank? || row[:first_name].blank? || row[:last_name].blank?

      ActiveRecord::Base.transaction do
        college_season = CollegeSeason.find_or_create_by!(college: college, season: @season)
        student = Student.find_or_create_for_college(first_name: row[:first_name], last_name: row[:last_name], college: college)
        student_season = StudentSeason.find_or_create_by!(student: student, college_season: college_season) do |ss|
          ss.position = row[:position]
          ss.class_year = row[:class_year]
        end

        honor = AllAmerican.find_or_initialize_by(
          student_season: student_season,
          national: group[:national],
          conference: group[:conference],
          preseason: group[:preseason]
        )
        honor.update!(tier: group[:tier])
      end
    end
  end
end
