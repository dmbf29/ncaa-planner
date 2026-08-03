class SeasonWeeksSerializer
  def initialize(season, week_numbers)
    @season = season
    @week_numbers = week_numbers
  end

  def as_json
    weeks = @week_numbers.filter_map { |number| week_json(number) }.sort_by { |w| -w[:week][:number] }

    {
      focus: focus_json(weeks.first),
      season: { id: @season.id, year: @season.year, dynasty: @season.dynasty.name },
      weeks: weeks
    }
  end

  private

  def focus_json(primary_week)
    return { instructions: "No matching weeks were found for the requested week_numbers." } unless primary_week

    label = week_label(primary_week[:week])
    {
      current_week: primary_week[:week][:number],
      instructions: "Focus primary commentary on #{label} below — its results and next-game previews. " \
                    "Any earlier weeks included are historical context only, not the main story."
    }
  end

  def week_label(week)
    return "the Conference Championship" if week[:conference_championship]
    return week[:name] || "the postseason" if week[:post_season]

    "Week #{week[:number]}"
  end

  def coached_college_seasons
    @coached_college_seasons ||= @season.college_seasons
                                         .includes(:college, :coach, :student_seasons)
                                         .where.not(coach_id: nil)
                                         .joins(:college)
                                         .order("colleges.name")
  end

  def coached_college_ids
    @coached_college_ids ||= coached_college_seasons.map(&:college_id).to_set
  end

  def all_games
    @all_games ||= Game.where(week_id: @season.week_ids)
                        .includes(:home_college, :away_college, :college_game_stats, :week)
                        .to_a
  end

  def games_for_college(college_id)
    all_games.select { |game| game.home_college_id == college_id || game.away_college_id == college_id }
             .sort_by { |game| game.week.number }
  end

  def week_json(number)
    week = @season.weeks.find_by(number: number)
    return nil unless week

    {
      week: {
        id: week.id,
        number: week.number,
        name: week.name,
        conference_championship: week.conference_championship,
        post_season: week.post_season
      },
      teams: coached_college_seasons.map { |cs| team_week_json(cs, week) },
      coached_matchups: coached_matchups_for_week(week)
    }
  end

  def team_week_json(college_season, week)
    games = games_for_college(college_season.college_id)
    this_week_game = games.find { |game| game.week_id == week.id }
    next_game = games.find { |game| game.week.number > week.number }

    {
      college: { id: college_season.college.id, name: college_season.college.name },
      coach: { id: college_season.coach.id, name: college_season.coach.name },
      record_entering_week: record_before(college_season.college_id, games, week.number),
      ranking: ranking_json(college_season.college_id, week),
      game: this_week_game_json(this_week_game, college_season.college_id),
      top_performers: top_performers_json(this_week_game, college_season),
      next_game: next_game && upcoming_game_json(next_game, college_season.college_id)
    }
  end

  def record_before(college_id, games, week_number)
    wins = 0
    losses = 0
    games.each do |game|
      next unless game.week.number < week_number

      result = game_result(game, college_id)
      next unless result

      result[:won] ? wins += 1 : losses += 1
    end
    { wins: wins, losses: losses }
  end

  def game_result(game, college_id)
    stats = game.college_game_stats.index_by(&:college_id)
    team_stat = stats[college_id]
    opponent_id = game.home_college_id == college_id ? game.away_college_id : game.home_college_id
    opponent_stat = stats[opponent_id]
    return nil unless team_stat&.final_score && opponent_stat&.final_score

    { team_score: team_stat.final_score, opponent_score: opponent_stat.final_score, won: team_stat.final_score > opponent_stat.final_score }
  end

  def this_week_game_json(game, college_id)
    return { status: "bye", opponent: nil, result: nil } unless game

    result = game_result(game, college_id)
    home = game.home_college_id == college_id
    opponent = home ? game.away_college : game.home_college
    {
      status: result ? "final" : "scheduled",
      opponent: opponent_json(opponent, home),
      result: result
    }
  end

  def upcoming_game_json(game, college_id)
    home = game.home_college_id == college_id
    opponent = home ? game.away_college : game.home_college
    { week_number: game.week.number, opponent: opponent_json(opponent, home) }
  end

  def opponent_json(opponent, home)
    { id: opponent.id, name: opponent.name, home: home, user_coached: coached_college_ids.include?(opponent.id) }
  end

  def ranking_json(college_id, week)
    current = CollegeWeekRanking.find_by(college_id: college_id, week_id: week.id)
    previous_week = @season.weeks.find_by(number: week.number - 1)
    previous = previous_week && CollegeWeekRanking.find_by(college_id: college_id, week_id: previous_week.id)

    {
      current_rank: current&.ranking,
      previous_rank: previous&.ranking,
      status: ranking_status(current, previous)
    }
  end

  def ranking_status(current, previous)
    return "unranked" unless current || previous
    return "entered_top_25" if current && !previous
    return "dropped_out_of_top_25" if previous && !current
    return "steady" if current.ranking == previous.ranking

    current.ranking < previous.ranking ? "moved_up" : "moved_down"
  end

  def top_performers_json(game, college_season)
    return [] unless game

    stat_columns = StudentGameStat.column_names - %w[id game_id student_season_id created_at updated_at]
    StudentGameStat.where(game_id: game.id, student_season_id: college_season.student_seasons.select(:id))
                   .includes(student_season: :student)
                   .map { |stat| performer_json(stat, stat_columns) }
  end

  def performer_json(stat, stat_columns)
    student_season = stat.student_season
    {
      name: student_season.student.name,
      position: student_season.position,
      stats: stat.attributes.slice(*stat_columns).compact.reject { |_key, value| value.zero? }
    }
  end

  def coached_matchups_for_week(week)
    all_games.select { |game| game.week_id == week.id && coached_college_ids.include?(game.home_college_id) && coached_college_ids.include?(game.away_college_id) }
             .map do |game|
      {
        home: { id: game.home_college.id, name: game.home_college.name },
        away: { id: game.away_college.id, name: game.away_college.name },
        result: game_result(game, game.home_college_id)
      }
    end
  end
end
