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
      college: { id: cwr.college.id, name: cwr.college.name, conference: cwr.college.conference },
      coached_by_us: coached_college_ids.include?(cwr.college_id),
      record: college_season && { wins: college_season.wins, losses: college_season.losses },
      last_result: college_season && last_result_json(college_season),
      next_game: college_season && next_game_json(college_season)
    }
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

  # The next game scheduled after this ranking's week — chronologically
  # after, so it's always "not yet played as of this week" by construction,
  # matching what a coach means by "who's up next" when browsing a past
  # week's rankings.
  def next_game_json(college_season)
    upcoming = college_season.games
                              .includes(:home_college, :away_college, :week)
                              .select { |g| g.week.number > @week.number }
                              .min_by { |g| g.week.number }
    return nil unless upcoming

    team_is_home = upcoming.home_college_id == college_season.college_id
    opponent_college = team_is_home ? upcoming.away_college : upcoming.home_college
    {
      week: { id: upcoming.week.id, number: upcoming.week.number, name: upcoming.week.name },
      opponent: { id: opponent_college.id, name: opponent_college.name, home: team_is_home }
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
