# Season-to-date team stats and individual stat leaders for one
# college_season — shared by SeasonDashboardSerializer (the dashboard team
# card, single leader per category + per-game averages) and
# SeasonWeeksSerializer (the weekly recap/preview broadcast, week 4 onward,
# top-N leaders per category + season totals) so both surfaces compute the
# same underlying numbers the same way.
class TeamSeasonStats
  # category => primary StudentGameStat column that decides that category's leader
  STAT_LEADER_CATEGORIES = {
    passing: :passing_yards,
    rushing: :rushing_yards,
    receiving: :receiving_yards,
    sacks: :defense_sacks,
    tackles: :defense_tackles,
    interceptions: :defense_interceptions
  }.freeze

  # How many leaders per category top_stat_leaders returns by default — a
  # starting QB is one story, but a receiving corps or a linebacker corps is
  # a rotation worth naming more than one player deep.
  DEFAULT_LEADER_LIMITS = {
    passing: 1, rushing: 2, receiving: 3, sacks: 2, tackles: 3, interceptions: 2
  }.freeze

  def initialize(college_season)
    @college_season = college_season
  end

  # Every played game for this team, paired with both sides' box score.
  def played_games
    @played_games ||= @college_season.games
                                      .includes(:college_game_stats)
                                      .map { |g| game_stat_pair(g) }
                                      .compact
  end

  # Team-level box score averages (yards/points per game), once this team
  # has any played games — nil until then, same convention as stat_leaders.
  def team_stats
    return nil if played_games.empty?

    {
      passing_offense: avg_stat { |g| g[:team_stat].passing_yards },
      rushing_offense: avg_stat { |g| g[:team_stat].rushing_yards },
      passing_defense: avg_stat { |g| g[:opponent_stat].passing_yards },
      rushing_defense: avg_stat { |g| g[:opponent_stat].rushing_yards },
      points_per_game: avg_stat { |g| g[:team_stat].final_score },
      points_against_per_game: avg_stat { |g| g[:opponent_stat].final_score }
    }
  end

  # Season totals (not per-game averages) — nil until this team has any
  # played games. sacks/interceptions are summed from the roster's
  # StudentGameStat defense columns since CollegeGameStat doesn't carry a
  # team-level defensive box score, only the offense's own box score plus
  # what it gave up.
  def team_totals
    return nil if played_games.empty?

    turnovers = total_stat { |g| g[:team_stat].turnovers }
    takeaways = total_stat { |g| g[:opponent_stat].turnovers }

    {
      passing_offense: total_stat { |g| g[:team_stat].passing_yards },
      rushing_offense: total_stat { |g| g[:team_stat].rushing_yards },
      passing_defense: total_stat { |g| g[:opponent_stat].passing_yards },
      rushing_defense: total_stat { |g| g[:opponent_stat].rushing_yards },
      points_for: total_stat { |g| g[:team_stat].final_score },
      points_against: total_stat { |g| g[:opponent_stat].final_score },
      turnovers: turnovers,
      takeaways: takeaways,
      turnover_margin: takeaways - turnovers,
      fumbles_lost: total_stat { |g| g[:team_stat].fumbles_lost },
      fumbles_recovered: total_stat { |g| g[:opponent_stat].fumbles_lost },
      sacks: defense_stat_total(:defense_sacks),
      # "Interceptions" is ambiguous on its own — thrown (a giveaway) or
      # taken away (a defensive playmaking stat)? This is specifically the
      # defense's picks, summed from the roster's own StudentGameStat rows
      # (same source as the stat-leader board), not CollegeGameStat's
      # interceptions_thrown column, which is this team's own giveaways.
      defensive_interceptions: defense_stat_total(:defense_interceptions),
      third_down_percentage: third_down_percentage,
      points_by_quarter: points_by_quarter_totals
    }
  end

  # Passing/rushing/receiving/sack/tackle/interception leaders for this team,
  # once it has any recorded game stats — nil until then. Returns
  # { category => { student_season:, value: } | nil }.
  def stat_leaders
    return nil if student_season_totals.empty?

    STAT_LEADER_CATEGORIES.transform_values { |column| category_leader(column) }
  end

  # Same idea as stat_leaders, but up to `limits[category]` players per
  # category (see DEFAULT_LEADER_LIMITS), sorted best-first. Returns
  # { category => [ { student_season:, value: }, ... ] } — an empty array
  # for a category with no positive totals, nil if this team has no
  # recorded game stats at all.
  def top_stat_leaders(limits = DEFAULT_LEADER_LIMITS)
    return nil if student_season_totals.empty?

    STAT_LEADER_CATEGORIES.each_with_object({}) do |(category, column), result|
      result[category] = category_leaders(column, limits.fetch(category, 1))
    end
  end

  private

  def game_stat_pair(game)
    stats = game.college_game_stats.index_by(&:college_id)
    team_stat = stats[@college_season.college_id]
    opponent_stat = stats.values.find { |s| s.college_id != @college_season.college_id }
    return nil unless team_stat&.final_score && opponent_stat&.final_score

    { team_stat: team_stat, opponent_stat: opponent_stat, won: team_stat.final_score > opponent_stat.final_score }
  end

  def avg_stat
    values = played_games.filter_map { |g| yield(g) }
    return nil if values.empty?

    (values.sum.to_f / values.size).round(1)
  end

  def total_stat
    played_games.sum { |g| yield(g) || 0 }
  end

  def third_down_percentage
    attempts = total_stat { |g| g[:team_stat].third_down_attempts }
    return nil if attempts.zero?

    conversions = total_stat { |g| g[:team_stat].third_down_conversions }
    ((conversions.to_f / attempts) * 100).round(1)
  end

  def points_by_quarter_totals
    {
      quarter_1: total_stat { |g| g[:team_stat].points_in_quarter_1 },
      quarter_2: total_stat { |g| g[:team_stat].points_in_quarter_2 },
      quarter_3: total_stat { |g| g[:team_stat].points_in_quarter_3 },
      quarter_4: total_stat { |g| g[:team_stat].points_in_quarter_4 },
      overtime: total_stat { |g| g[:team_stat].points_in_overtime }
    }
  end

  def student_season_totals
    return @student_season_totals if defined?(@student_season_totals)

    game_stats = StudentGameStat.joins(:student_season)
                                 .where(student_seasons: { college_season_id: @college_season.id })
                                 .includes(student_season: :student)
                                 .to_a

    @student_season_totals = game_stats.group_by(&:student_season).transform_values do |rows|
      STAT_LEADER_CATEGORIES.values.index_with { |column| rows.sum { |r| r.public_send(column) || 0 } }
    end
  end

  def defense_stat_total(column)
    student_season_totals.values.sum { |totals| totals[column] }
  end

  def category_leader(column)
    student_season, totals = student_season_totals.select { |_ss, totals| totals[column].positive? }
                                                     .max_by { |_ss, totals| totals[column] }
    return nil unless student_season

    { student_season: student_season, value: totals[column] }
  end

  def category_leaders(column, limit)
    student_season_totals.select { |_ss, totals| totals[column].positive? }
                          .sort_by { |_ss, totals| -totals[column] }
                          .first(limit)
                          .map { |student_season, totals| { student_season: student_season, value: totals[column] } }
  end
end
