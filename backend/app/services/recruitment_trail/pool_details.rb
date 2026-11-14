module RecruitmentTrail
  # Fills in what the signing screen doesn't show ("G. Cushenberry" has no first name) from Dynasty
  # Rewired's recruit pool, so the review screen needs no typing. Only recruits (not transfers, which
  # link to a player on their old roster) that match exactly one pool recruit are filled in; anything
  # else is left for the reviewer as before. A pool that can't be read leaves the extract untouched,
  # since the upload must not fail over an optional lookup.
  class PoolDetails
    def initialize(season, pool: DynastyRewired::RecruitPool.new(season))
      @pool = pool
    end

    def call(result)
      result.merge(recruits: result[:recruits].map { |row| fill(row) })
    rescue DynastyRewired::Client::Error => e
      Rails.logger.warn("RecruitmentTrail pool lookup skipped: #{e.message}")
      result
    end

    private

    def fill(row)
      return row if row[:transfer] || row[:first_name].present?

      recruit = @pool.match(first_initial: row[:first_initial], last_name: row[:last_name], state: row[:state], national_rank: row[:national_rank])
      return row unless recruit

      row.merge(
        first_name: recruit[:first_name],
        star_rating: row[:star_rating] || recruit[:stars],
        national_rank: row[:national_rank] || recruit[:rank],
        position_rank: row[:position_rank] || recruit[:position_rank],
        state_rank: row[:state_rank] || recruit[:state_rank],
        pool_match: true
      )
    end
  end
end
