# A player's season-to-date box score through a given week, grouped into the
# same passing/rushing/receiving/defense buckets as everywhere else and
# aggregated by PlayerStatTotals. Only buckets with real production are
# kept; nil when the player has no recorded stats yet (e.g. an O-lineman, or
# someone hurt in week 1) so callers can stay silent.
class PlayerSeasonStats
  def self.call(student_season, through_week_number:)
    new(student_season, through_week_number).call
  end

  def initialize(student_season, through_week_number)
    @student_season = student_season
    @through_week_number = through_week_number
  end

  def call
    rows = StudentGameStat.joins(game: :week)
                          .where(student_season_id: @student_season.id)
                          .where(weeks: { number: ..@through_week_number })
                          .to_a
    return nil if rows.empty?

    totals = PlayerStatTotals.call(rows)
    buckets = {
      passing: passing_bucket(totals),
      rushing: rushing_bucket(totals),
      receiving: receiving_bucket(totals),
      defense: defense_bucket(totals)
    }.compact
    return nil if buckets.empty?

    { games_played: totals[:games_played] }.merge(buckets)
  end

  private

  def passing_bucket(totals)
    return nil unless totals[:passing_attempts].to_i.positive?

    {
      completions: totals[:passing_completions], attempts: totals[:passing_attempts],
      yards: totals[:passing_yards], tds: totals[:passing_tds],
      interceptions: totals[:passing_interceptions], rating: totals[:passing_rating]
    }
  end

  def rushing_bucket(totals)
    return nil unless totals[:rushing_carries].to_i.positive?

    {
      carries: totals[:rushing_carries], yards: totals[:rushing_yards],
      avg: totals[:rushing_avg], tds: totals[:rushing_tds]
    }
  end

  def receiving_bucket(totals)
    return nil unless totals[:receiving_receptions].to_i.positive?

    {
      receptions: totals[:receiving_receptions], yards: totals[:receiving_yards],
      avg: totals[:receiving_avg], tds: totals[:receiving_tds]
    }
  end

  def defense_bucket(totals)
    keys = %i[defense_tackles defense_tfl defense_sacks defense_interceptions]
    return nil unless keys.any? { |key| totals[key].to_f.positive? }

    {
      tackles: totals[:defense_tackles], tfl: totals[:defense_tfl],
      sacks: totals[:defense_sacks], interceptions: totals[:defense_interceptions]
    }
  end
end
