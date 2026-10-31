module RankingStats
  # Persists a (possibly user-edited) Top 25 for one week: replaces that week's CollegeWeekRanking rows and backfills
  # last week's ranking where it's missing. It only tracks the poll — games and records come from the schedule and
  # box scores, so nothing here creates a Game or touches a CollegeSeason.
  class CommitService
    def initialize(week)
      @week = week
      @season = week.season
    end

    # Returns a list of { rank:, error: } for any row that couldn't be saved; the rest are still saved.
    def call(rows)
      rows = Array(rows).map(&:deep_symbolize_keys).select { |row| row[:rank].present? && College.exists?(row[:college_id]) }
      warnings = []

      ActiveRecord::Base.transaction do
        @week.college_week_rankings.where.not(college_id: rows.pluck(:college_id)).destroy_all
        rows.each do |row|
          commit_row(row)
        rescue ActiveRecord::RecordInvalid => e
          warnings << { rank: row[:rank], error: e.message }
        end
      end
      warnings
    end

    private

    def commit_row(row)
      college = College.find(row[:college_id])
      # Free the slot first so two teams swapping ranks within a save don't trip the per-week uniqueness check.
      @week.college_week_rankings.where(ranking: row[:rank]).where.not(college_id: college.id).destroy_all
      CollegeWeekRanking.find_or_initialize_by(college: college, week: @week).update!(ranking: row[:rank])
      backfill_last_week_ranking(college, row[:lw_ranking])
    end

    def backfill_last_week_ranking(college, lw_ranking)
      return if lw_ranking.blank? || previous_week.blank?

      CollegeWeekRanking.find_or_create_by!(college: college, week: previous_week) do |ranking|
        ranking.ranking = lw_ranking
      end
    end

    def previous_week
      @previous_week ||= Week.find_by(season: @season, number: @week.number - 1)
    end
  end
end
