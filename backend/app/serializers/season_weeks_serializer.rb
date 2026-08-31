class SeasonWeeksSerializer
  # Season-to-date stat leaders/team stats are noisy over a tiny sample, so
  # they only start showing up in the recap once a team has a few games of
  # data behind it.
  MIN_WEEK_NUMBER_FOR_SEASON_STATS = 4

  def initialize(season, week_numbers)
    @season = season
    @week_numbers = week_numbers
  end

  def as_json
    weeks = @week_numbers.filter_map { |number| week_json(number) }.sort_by { |w| -w[:week][:number] }

    {
      focus: focus_json(weeks.first),
      season: {
        id: @season.id,
        year: @season.year,
        dynasty: @season.dynasty.name,
        coached_conferences: coached_conferences
      },
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
                                         .includes(:college, :coach, :student_seasons, signed_recruits: :week)
                                         .where.not(coach_id: nil)
                                         .joins(:college)
                                         .order("colleges.name")
  end

  def coached_college_ids
    @coached_college_ids ||= coached_college_seasons.map(&:college_id).to_set
  end

  # The conference(s) our coached teams play in — used to scope the "around
  # the conference" scoreboard to results relevant to our dynasty rather
  # than every other game league-wide.
  def coached_conferences
    @coached_conferences ||= coached_college_seasons.map(&:conference).uniq
  end

  def college_seasons_by_college_id
    @college_seasons_by_college_id ||= @season.college_seasons.index_by(&:college_id)
  end

  def conference_for(college_id)
    college_seasons_by_college_id[college_id]&.conference
  end

  def all_games
    @all_games ||= Game.where(week_id: @season.week_ids)
                        .includes(:home_college, :away_college, :college_game_stats, :week,
                                  offensive_player_of_game: [ :student, { college_season: :college } ],
                                  defensive_player_of_game: [ :student, { college_season: :college } ])
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
      top_25: top_25_for_week(week),
      bowl_projections: bowl_projections_for_week(week),
      coached_matchups: coached_matchups_for_week(week),
      conference_results: conference_results_for_week(week),
      conference_top_25: conference_top_25_for_week(week),
      conference_heisman_watch: conference_heisman_watch_for_week(week),
      conference_standings: week.number >= MIN_WEEK_NUMBER_FOR_SEASON_STATS ? conference_standings_json : nil
    }
  end

  # The full national Top 25 poll released AFTER this week's games — every
  # currently-ranked team, not just conference rivals (see
  # conference_top_25_for_week, which only reports conference movement). A
  # given Week's own CollegeWeekRankings are the poll entering that week
  # (before its games), same convention as ranking_json/record_entering_week
  # elsewhere in this file — so recapping week N's results wants week N+1's
  # poll, the freshest one that actually reflects those results. Absent
  # entirely (not falling back to an older poll) if that next poll hasn't
  # been entered yet.
  def top_25_for_week(week)
    poll_week = @season.weeks.find_by(number: week.number + 1)
    return [] unless poll_week

    rankings = poll_week.college_week_rankings.includes(:college).order(:ranking).to_a
    return [] if rankings.empty?

    previous_by_college = week.college_week_rankings.index_by(&:college_id)

    rankings.map { |cwr| top_25_ranking_json(cwr, poll_week, previous_by_college[cwr.college_id]) }
  end

  def top_25_ranking_json(cwr, poll_week, previous)
    college = cwr.college
    {
      rank: cwr.ranking,
      previous_rank: previous&.ranking,
      status: ranking_status(cwr, previous),
      college: { id: college.id, name: college.name, conference: conference_for(college.id) },
      coached_by_us: coached_college_ids.include?(college.id),
      record: record_before(college.id, games_for_college(college.id), poll_week.number)
    }
  end

  # Bowl projections for the week AFTER week — same "N+1" convention as
  # top_25_for_week, since projections are only ever captured on a handful
  # of weeks (see BowlProjection's doc comment) rather than every week, so
  # week N's episode surfaces whichever projection screenshot was taken
  # going into week N+1. Empty (not included in the recap) unless that
  # next week actually has projections on record.
  def bowl_projections_for_week(week)
    preview_week = @season.weeks.find_by(number: week.number + 1)
    return [] unless preview_week

    preview_week.bowl_projections
                .includes(:projected_home_college, :projected_away_college)
                .order(:time)
                .map { |bp| bowl_projection_json(bp) }
  end

  def bowl_projection_json(bp)
    {
      bowl_name: bp.bowl_name,
      cfp_round: bp.cfp_round,
      time: bp.time,
      projected_home: bp.projected_home_college&.name,
      projected_away: bp.projected_away_college&.name
    }
  end

  # The full standings table (same numbers as the public Conference
  # Standings page) for only the conference(s) our coached teams play in —
  # not every conference in the league. It's a current snapshot, not
  # week-specific data (see ConferenceStandings::CommitService), so it's the
  # same for every week in this response — memoized rather than recomputed
  # per week.
  def conference_standings_json
    @conference_standings_json ||= ConferenceStandingsSerializer.new(@season)
                                                                  .as_json[:conferences]
                                                                  .select { |c| coached_conferences.include?(c[:conference]) }
  end

  def team_week_json(college_season, week)
    games = games_for_college(college_season.college_id)
    this_week_game = games.find { |game| game.week_id == week.id }
    next_game = games.find { |game| game.week.number > week.number }

    {
      college: { id: college_season.college.id, name: college_season.college.name },
      coach: coach_json(college_season.coach),
      record_entering_week: record_before(college_season.college_id, games, week.number),
      ranking: ranking_json(college_season.college_id, week),
      game: this_week_game_json(this_week_game, college_season.college_id),
      top_performers: top_performers_json(this_week_game, college_season),
      players_of_the_week: players_of_the_week_json(college_season, week),
      recruiting_trail: recruiting_trail_json(college_season, week),
      injury_report: injury_report_json(college_season, week),
      next_game: next_game && upcoming_game_json(next_game, college_season.college_id),
      season_stats: week.number >= MIN_WEEK_NUMBER_FOR_SEASON_STATS ? season_stats_json(college_season) : nil
    }
  end

  # Same season-to-date numbers as the dashboard's team card ("Stat Leaders"
  # and "Team Stats per Game"), plus a broadcast-only expanded view: multiple
  # leaders per category and season totals (not just per-game averages) —
  # see TeamSeasonStats.
  def season_stats_json(college_season)
    stats = TeamSeasonStats.new(college_season)

    {
      stat_leaders: stat_leaders_json(stats.top_stat_leaders),
      team_stats: stats.team_stats,
      team_totals: stats.team_totals
    }
  end

  def stat_leaders_json(leaders)
    return nil unless leaders

    leaders.transform_values { |list| list.map { |leader| stat_leader_json(leader) } }
  end

  def stat_leader_json(leader)
    student_season = leader[:student_season]
    { name: student_season.student.name, position: student_season.position, value: leader[:value] }
  end

  # Injuries active as of this week (see Injury#active_as_of?).
  def injury_report_json(college_season, week)
    college_season.student_seasons
                  .includes(:student, injuries: { game: :week })
                  .flat_map(&:injuries)
                  .select { |injury| injury.active_as_of?(week) }
                  .map { |injury| injury_report_entry_json(injury) }
  end

  def injury_report_entry_json(injury)
    student_season = injury.student_season
    {
      name: student_season.student.name,
      position: student_season.position,
      description: injury.description,
      injured_week_number: injury.game.week.number,
      status: injury.out_for_season? ? "out_for_season" : "expected_back_week_#{injury.return_week_number}"
    }
  end

  # This team's National/Conference Player(s) of the Week for this week, if
  # any — nil-shaped per side, mirroring player_of_game_json.
  def players_of_the_week_json(college_season, week)
    awards = week.players_of_the_week
                 .joins(:student_season)
                 .where(student_seasons: { college_season_id: college_season.id })
                 .includes(student_season: :student)

    {
      offensive: player_of_the_week_json(awards.find { |award| award.side == "offensive" }),
      defensive: player_of_the_week_json(awards.find { |award| award.side == "defensive" })
    }
  end

  def player_of_the_week_json(award)
    return nil unless award

    {
      name: award.student_season.student.name,
      position: award.student_season.position,
      stat_line: award.stat_line,
      national: award.national,
      conference: award.conference
    }
  end

  # Recruits this team signed that were first recorded in THIS week — the
  # "newly signed this week" list, so a recap mentions each signing once,
  # the week it happens, rather than re-reading the whole class every week.
  # Silent (empty array) for a week with no new signings.
  def recruiting_trail_json(college_season, week)
    college_season.signed_recruits
                  .select { |recruit| recruit.week_id == week.id }
                  .sort_by { |recruit| [ -(recruit.star_rating || 0), recruit.national_rank || Float::INFINITY, recruit.last_name.to_s ] }
                  .map { |recruit| recruit_json(recruit) }
  end

  def recruit_json(recruit)
    {
      name: recruit.name,
      position: recruit.position,
      star_rating: recruit.star_rating,
      nil_amount: recruit.nil_amount,
      national_rank: recruit.national_rank,
      position_rank: recruit.position_rank,
      state_rank: recruit.state_rank,
      state: recruit.state
    }
  end

  def coach_json(coach)
    {
      id: coach.id,
      name: coach.name,
      offensive_scheme: coach.offensive_scheme,
      defensive_scheme: coach.defensive_scheme
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
      bowl_name: game.bowl_name,
      cfp_round: game.cfp_round,
      opponent: opponent_json(opponent, home),
      result: result,
      narrative_summary: result ? game.narrative_summary : nil,
      offensive_player_of_game: result ? player_of_game_json(game.offensive_player_of_game, game.offensive_player_stat_line) : nil,
      defensive_player_of_game: result ? player_of_game_json(game.defensive_player_of_game, game.defensive_player_stat_line) : nil,
      team_stats: result ? team_stats_json(game, college_id, opponent.id) : nil
    }
  end

  # Full-game box score comparison for both sides — nil when either side is
  # missing a CollegeGameStat row (shouldn't happen once `result` is
  # present, since game_result already requires both final_scores, but the
  # rest of the box score is a separate set of columns that could in theory
  # lag behind).
  def team_stats_json(game, college_id, opponent_id)
    stats = game.college_game_stats.index_by(&:college_id)
    team_stat = stats[college_id]
    opponent_stat = stats[opponent_id]
    return nil unless team_stat && opponent_stat

    { team: box_score_json(team_stat), opponent: box_score_json(opponent_stat) }
  end

  def box_score_json(stat)
    stat.attributes.symbolize_keys.slice(*box_score_columns)
  end

  # Every CollegeGameStat column that isn't a row identifier/timestamp —
  # the full box score, not a curated subset, so nothing gets left out as
  # more columns are added to the schema.
  def box_score_columns
    @box_score_columns ||= (CollegeGameStat.column_names - %w[id game_id college_id created_at updated_at]).map(&:to_sym)
  end

  def player_of_game_json(student_season, stat_line)
    return nil unless student_season

    {
      name: student_season.student.name,
      position: student_season.position,
      college: student_season.college_season.college.name,
      stat_line: stat_line
    }
  end

  def upcoming_game_json(game, college_id)
    home = game.home_college_id == college_id
    opponent = home ? game.away_college : game.home_college
    {
      week_number: game.week.number,
      bowl_name: game.bowl_name,
      cfp_round: game.cfp_round,
      opponent: opponent_json(opponent, home),
      opponent_record: record_before(opponent.id, games_for_college(opponent.id), game.week.number),
      opponent_last_result: opponent_last_result_json(opponent.id, game.week.number),
      opponent_schedule: opponent_schedule_json(opponent.id, game.week.number),
      scouting_report: scouting_report_json(opponent.id)
    }
  end

  # The opponent's full schedule for every week before before_week_number,
  # in order — same per-week final/bye/missing logic as
  # opponent_last_result_json, just for the whole season so far instead of
  # one week, so a recap can give real context on how the opponent's been
  # playing rather than just their most recent score. Empty for a Week 1
  # opponent (nothing came before it).
  def opponent_schedule_json(opponent_id, before_week_number)
    games = games_for_college(opponent_id)
    bye_week_ids = college_seasons_by_college_id[opponent_id]&.bye_week_ids || []

    @season.weeks.where("number < ?", before_week_number).order(:number).map do |week|
      opponent_schedule_week_json(opponent_id, week, games, bye_week_ids)
    end
  end

  def opponent_schedule_week_json(opponent_id, week, games, bye_week_ids)
    week_json = { id: week.id, number: week.number, name: week.name }
    game = games.find { |g| g.week_id == week.id }
    result = game && game_result(game, opponent_id)

    if result
      home = game.home_college_id == opponent_id
      versus = home ? game.away_college : game.home_college
      return { status: "final", week: week_json, opponent: opponent_json(versus, home), result: result }
    end

    return { status: "bye", week: week_json } if bye_week_ids.include?(week.id)

    { status: "missing", week: week_json }
  end

  # What happened for this opponent the single week before before_week_number
  # — not a multi-week backward scan, since the point of this is to surface
  # a gap ("missing") rather than quietly search past it for an older
  # result. A week with no game is only reported as "bye" if it's in
  # CollegeSeason#bye_week_ids (the only place that fact is ever recorded —
  # see TeamSchedule::CommitService); otherwise it's "missing" — that
  # team's data for that week just hasn't been uploaded yet. nil when
  # before_week_number is the season's first week (nothing came before it).
  def opponent_last_result_json(opponent_id, before_week_number)
    week = @season.weeks.find_by(number: before_week_number - 1)
    return nil unless week

    game = games_for_college(opponent_id).find { |g| g.week_id == week.id }
    result = game && game_result(game, opponent_id)

    if result
      home = game.home_college_id == opponent_id
      versus = home ? game.away_college : game.home_college
      return { status: "final", week_number: week.number, opponent: opponent_json(versus, home), result: result }
    end

    bye_week_ids = college_seasons_by_college_id[opponent_id]&.bye_week_ids || []
    return { status: "bye", week_number: week.number } if bye_week_ids.include?(week.id)

    { status: "missing", week_number: week.number }
  end

  # Overall/offense/defense ratings plus the one player to watch on each
  # side of the ball for a not-yet-played opponent — nil-shaped when the
  # opponent has no CollegeSeason on record for this season.
  def scouting_report_json(college_id)
    college_season = college_seasons_by_college_id[college_id]
    return { overall: nil, offense: nil, defense: nil, best_offensive_player: nil, best_defensive_player: nil } unless college_season

    {
      overall: college_season.overall,
      offense: college_season.offense,
      defense: college_season.defense,
      best_offensive_player: scouting_player_json(college_season.best_offensive_players(limit: 1).first),
      best_defensive_player: scouting_player_json(college_season.best_defensive_players(limit: 1).first)
    }
  end

  def scouting_player_json(student_season)
    return nil unless student_season

    { name: student_season.student.name, position: student_season.position, overall: student_season.overall }
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

  # Position codes that get pulled to the front of each team's performer
  # list, in this order — everything else keeps its natural (name) order
  # after them.
  TOP_PERFORMER_POSITION_PRIORITY = %w[QB HB WR].freeze

  def top_performers_json(game, college_season)
    return nil unless game

    home = college_season.college_id == game.home_college_id
    opponent_college = home ? game.away_college : game.home_college

    {
      team: team_performers_json(game, college_season, college_season.college),
      opponent: team_performers_json(game, college_seasons_by_college_id[opponent_college.id], opponent_college)
    }
  end

  def team_performers_json(game, college_season, college)
    performers = college_season ? performers_for(game, college_season) : []
    { college: { id: college.id, name: college.name }, performers: sort_performers(performers) }
  end

  def performers_for(game, college_season)
    stat_columns = StudentGameStat.column_names - %w[id game_id student_season_id created_at updated_at]
    StudentGameStat.where(game_id: game.id, student_season_id: college_season.student_seasons.select(:id))
                   .includes(student_season: :student)
                   .map { |stat| performer_json(stat, stat_columns) }
  end

  def sort_performers(performers)
    performers.sort_by do |performer|
      priority = TOP_PERFORMER_POSITION_PRIORITY.index(performer[:position])
      [ priority || TOP_PERFORMER_POSITION_PRIORITY.size, performer[:name] ]
    end
  end

  def performer_json(stat, stat_columns)
    student_season = stat.student_season
    {
      name: student_season.student.name,
      position: student_season.position,
      stats: stat.attributes.slice(*stat_columns).compact.reject { |_key, value| value.zero? }
    }
  end

  def conference_results_for_week(week)
    all_games.select { |game| game.week_id == week.id }
             .reject { |game| coached_college_ids.include?(game.home_college_id) || coached_college_ids.include?(game.away_college_id) }
             .select { |game| coached_conferences.include?(conference_for(game.home_college_id)) || coached_conferences.include?(conference_for(game.away_college_id)) }
             .filter_map { |game| conference_game_json(game) }
  end

  def conference_game_json(game)
    stats = game.college_game_stats.index_by(&:college_id)
    home_stat = stats[game.home_college_id]
    away_stat = stats[game.away_college_id]
    return nil unless home_stat&.final_score && away_stat&.final_score

    {
      home: { id: game.home_college.id, name: game.home_college.name },
      away: { id: game.away_college.id, name: game.away_college.name },
      result: { home_score: home_stat.final_score, away_score: away_stat.final_score }
    }
  end

  # Top 25 movement for conference rivals (excludes our own coached teams,
  # whose ranking is already shown in their own team section) — anyone who
  # entered, moved, held steady, or dropped out, between last week and this
  # one. Empty when no conference team appears in either week's poll.
  def conference_top_25_for_week(week)
    previous_week = @season.weeks.find_by(number: week.number - 1)
    current_by_college = week.college_week_rankings.includes(:college).index_by(&:college_id)
    previous_by_college = previous_week ? previous_week.college_week_rankings.includes(:college).index_by(&:college_id) : {}

    relevant_college_ids = (current_by_college.keys + previous_by_college.keys).uniq.select do |college_id|
      coached_conferences.include?(conference_for(college_id)) && !coached_college_ids.include?(college_id)
    end

    relevant_college_ids.map do |college_id|
      current = current_by_college[college_id]
      previous = previous_by_college[college_id]
      college = (current || previous).college

      {
        college: { id: college.id, name: college.name },
        current_rank: current&.ranking,
        previous_rank: previous&.ranking,
        status: ranking_status(current, previous)
      }
    end.sort_by { |ranking| ranking[:current_rank] || ranking[:previous_rank] }
  end

  # Heisman watch adds/drops for conference rivals (excludes our own coached
  # teams' players) between last week and this one. Empty when no conference
  # player appears on the watch list in either week.
  def conference_heisman_watch_for_week(week)
    previous_week = @season.weeks.find_by(number: week.number - 1)
    student_season_includes = { student_season: [ :student, { college_season: :college } ] }
    current_by_student_season = week.heisman_candidates.includes(student_season_includes).index_by(&:student_season_id)
    previous_by_student_season = previous_week ? previous_week.heisman_candidates.includes(student_season_includes).index_by(&:student_season_id) : {}

    relevant_student_season_ids = (current_by_student_season.keys + previous_by_student_season.keys).uniq.select do |student_season_id|
      candidate = current_by_student_season[student_season_id] || previous_by_student_season[student_season_id]
      college_season = candidate.student_season.college_season
      coached_conferences.include?(college_season.conference) && !coached_college_ids.include?(college_season.college_id)
    end

    relevant_student_season_ids.map do |student_season_id|
      current = current_by_student_season[student_season_id]
      previous = previous_by_student_season[student_season_id]
      student_season = (current || previous).student_season
      college = student_season.college_season.college

      {
        student: { name: student_season.student.name, position: student_season.position },
        college: { id: college.id, name: college.name },
        status: heisman_watch_status(current, previous)
      }
    end
  end

  def heisman_watch_status(current, previous)
    return "added" if current && !previous
    return "dropped" if previous && !current

    "steady"
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
