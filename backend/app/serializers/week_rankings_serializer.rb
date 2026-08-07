# The full Top 25 for one specific week, plus the list of every week in the
# season that actually has rankings entered — so the frontend can build a
# week picker without a second request. Standalone from
# SeasonDashboardSerializer#top_25 (which only ever shows the latest ranked
# week) since this powers a historical, pick-any-week view.
class WeekRankingsSerializer
  def initialize(week)
    @week = week
  end

  def as_json
    {
      week: { id: @week.id, number: @week.number, name: @week.name },
      rankings: rankings_json,
      ranked_weeks: ranked_weeks_json
    }
  end

  private

  def coached_college_ids
    @coached_college_ids ||= @week.season.college_seasons.where.not(coach_id: nil).pluck(:college_id).to_set
  end

  def college_seasons_by_college_id
    @college_seasons_by_college_id ||= @week.season.college_seasons.index_by(&:college_id)
  end

  def rankings_json
    @week.college_week_rankings
         .includes(:college)
         .order(:ranking)
         .map { |cwr| ranking_json(cwr) }
  end

  def ranking_json(cwr)
    college_season = college_seasons_by_college_id[cwr.college_id]

    {
      rank: cwr.ranking,
      rank_trend: rank_trend(cwr.ranking, previous_rankings_by_college_id[cwr.college_id]),
      college: { id: cwr.college.id, name: cwr.college.name, conference: cwr.college.conference },
      coached_by_us: coached_college_ids.include?(cwr.college_id),
      record: college_season && { wins: college_season.wins, losses: college_season.losses },
      this_week: this_week_matchup_json(cwr.college_id),
      last_result: college_season && last_result_json(college_season)
    }
  end

  # The most recent ranking each currently-ranked college held before this
  # week — skips over any weeks that don't have rankings entered, same
  # "most recently entered" convention used throughout this serializer.
  def previous_rankings_by_college_id
    return @previous_rankings_by_college_id if defined?(@previous_rankings_by_college_id)

    rows = CollegeWeekRanking.joins(:week)
                              .where(weeks: { season_id: @week.season_id })
                              .where("weeks.number < ?", @week.number)
                              .select("college_week_rankings.college_id, college_week_rankings.ranking, weeks.number AS week_number")

    @previous_rankings_by_college_id = rows.group_by(&:college_id).transform_values do |college_rows|
      college_rows.max_by(&:week_number).ranking
    end
  end

  def rank_trend(current_rank, previous_rank)
    return nil if previous_rank.nil?
    return "same" if current_rank == previous_rank

    current_rank < previous_rank ? "up" : "down"
  end

  # Every game being played in this week, indexed by each side's
  # college_id — "who's on deck" for a Top 25 team this week.
  def this_week_games_by_college_id
    @this_week_games_by_college_id ||= Game.where(week_id: @week.id)
                                            .includes(:home_college, :away_college)
                                            .each_with_object({}) do |game, hash|
      hash[game.home_college_id] = game
      hash[game.away_college_id] = game
    end
  end

  def this_week_matchup_json(college_id)
    game = this_week_games_by_college_id[college_id]
    return nil unless game

    home = game.home_college_id == college_id
    opponent = home ? game.away_college : game.home_college
    { opponent: { id: opponent.id, name: opponent.name, rank: rank_for_college(opponent.id) }, home: home }
  end

  def latest_ranked_college_ids
    @latest_ranked_college_ids ||= @week.college_week_rankings.index_by(&:college_id)
  end

  def rank_for_college(college_id)
    latest_ranked_college_ids[college_id]&.ranking
  end

  # The most recent played game through this ranking's week — "how'd they
  # do last time out," as of the week being viewed (rankings can be viewed
  # for any past week, not just the latest).
  def last_result_json(college_season)
    game = college_season.games
                          .includes(:home_college, :away_college, :college_game_stats, :week)
                          .select { |g| g.week.number <= @week.number && g.played? }
                          .max_by { |g| g.week.number }
    return nil unless game

    stats = game.college_game_stats.index_by(&:college_id)
    team_stat = stats[college_season.college_id]
    opponent_college = game.home_college_id == college_season.college_id ? game.away_college : game.home_college
    opponent_stat = stats[opponent_college.id]
    return nil unless team_stat&.final_score && opponent_stat&.final_score

    {
      opponent: { id: opponent_college.id, name: opponent_college.name },
      team_score: team_stat.final_score,
      opponent_score: opponent_stat.final_score,
      won: team_stat.final_score > opponent_stat.final_score
    }
  end

  def ranked_weeks_json
    @week.season.weeks
         .joins(:college_week_rankings)
         .distinct
         .order(:number)
         .map { |week| { id: week.id, number: week.number, name: week.name } }
  end
end
