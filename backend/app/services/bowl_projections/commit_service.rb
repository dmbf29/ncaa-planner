module BowlProjections
  # Persists a (possibly user-edited) bowl projections extraction for one
  # observation week: upserts a BowlProjection per row, keyed by
  # (week, bowl_name) so re-uploading a corrected or more recent
  # screenshot for the same week refreshes existing rows instead of
  # duplicating them. Each row commits independently — one bad row
  # doesn't block the rest — mirroring RankingStats::CommitService.
  class CommitService
    def initialize(week)
      @week = week
    end

    def call(rows)
      Array(rows).filter_map do |row|
        symbolized = row.deep_symbolize_keys
        commit_row(symbolized)
        nil
      rescue ActiveRecord::RecordInvalid => e
        { bowl_name: symbolized[:bowl_name], error: e.message }
      end
    end

    private

    def commit_row(row)
      return if row[:bowl_name].blank?

      projection = @week.bowl_projections.find_or_initialize_by(bowl_name: row[:bowl_name])
      projection.update!(
        cfp_round: row[:cfp_round],
        projected_away_college_id: row[:away_college_id],
        projected_home_college_id: row[:home_college_id]
      )
    end
  end
end
