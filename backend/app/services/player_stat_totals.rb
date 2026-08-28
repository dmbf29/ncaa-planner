# Aggregates a collection of StudentGameStat rows (one player, any number of
# games) into a single stat line. Counting stats sum; "longest play" columns
# take the max (summing them would be meaningless); rate stats are
# recomputed from the summed counts rather than summed/averaged directly.
class PlayerStatTotals
  SUM_FIELDS = {
    passing: %i[passing_completions passing_attempts passing_yards passing_tds passing_interceptions
                passing_sacks_taken],
    rushing: %i[rushing_carries rushing_yards rushing_tds rushing_fumbles rushing_yac],
    receiving: %i[receiving_receptions receiving_yards receiving_tds receiving_rac receiving_drop],
    defense: %i[defense_solo_tackles defense_assist_tackles defense_tackles defense_tfl defense_sacks
                defense_interceptions]
  }.freeze

  MAX_FIELDS = {
    passing: %i[passing_longest],
    rushing: %i[rushing_longest],
    receiving: %i[receiving_longest],
    defense: %i[defense_interceptions_longest]
  }.freeze

  def self.call(game_stats)
    new(game_stats).totals
  end

  def initialize(game_stats)
    @game_stats = game_stats
  end

  def totals
    result = { games_played: @game_stats.size }
    SUM_FIELDS.each_value { |fields| fields.each { |field| result[field] = sum(field) } }
    MAX_FIELDS.each_value { |fields| fields.each { |field| result[field] = max(field) } }
    result[:passing_avg] = percentage(result[:passing_completions], result[:passing_attempts])
    result[:rushing_avg] = rate(result[:rushing_yards], result[:rushing_carries])
    result[:receiving_avg] = rate(result[:receiving_yards], result[:receiving_receptions])
    result[:passing_rating] = average(:passing_rating)
    result
  end

  private

  def sum(field)
    @game_stats.sum { |row| row.public_send(field) || 0 }
  end

  def max(field)
    @game_stats.filter_map(&field).max
  end

  def average(field)
    values = @game_stats.filter_map(&field)
    return nil if values.empty?

    (values.sum / values.size).round(1)
  end

  def percentage(made, attempts)
    return nil if attempts.nil? || attempts.zero?

    ((made.to_f / attempts) * 100).round(1)
  end

  def rate(total, count)
    return nil if count.nil? || count.zero?

    (total.to_f / count).round(1)
  end
end
