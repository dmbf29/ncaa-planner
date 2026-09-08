class SeasonWeeksSerializer
  # Season-to-date stat leaders/team stats are noisy over a tiny sample, so
  # they only start showing up in the recap once a team has a few games of
  # data behind it.
  MIN_WEEK_NUMBER_FOR_SEASON_STATS = 4

  # The projected conference-championship matchup only shows up once the
  # conference races have taken shape — from the Week 11 recap on.
  MIN_WEEK_NUMBER_FOR_CHAMPIONSHIP_PROJECTION = 10

  # Last week of the regular season (Season#create_weeks: 0–14 regular, 15
  # conference championship, 16–19 bowls). Once a review is at or past this
  # week and a team has no game scheduled beyond it, its season is treated
  # as complete rather than "schedule not uploaded yet".
  REGULAR_SEASON_FINAL_WEEK = 14

  # Wins needed to be bowl eligible.
  BOWL_ELIGIBILITY_WINS = 6

  def initialize(season, week_numbers)
    @season = season
    @week_numbers = week_numbers
  end

  def as_json
    weeks = @week_numbers.filter_map { |number| week_json(number) }.sort_by { |w| -w[:week][:number] }

    {
      focus: focus_json(weeks.first),
      podcast_date: podcast_date_json,
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

  # The in-world date the episode is being recorded, so the hosts have a
  # concrete "when": the day after the primary week's last game. If that
  # week has no game with a known kickoff on record (e.g. Week 14, which is
  # just Army–Navy and often has no time set), fall back to the day before
  # the first game of the week being previewed. nil when neither week has a
  # game time to anchor to. Game times carry a real calendar year off the
  # season (see TeamSchedule::CommitService / ScheduleStats::CommitService),
  # so this stays correct across seasons.
  def podcast_date_json
    number = primary_week_number
    return nil unless number

    last_game = latest_game_time_in_week(@season.weeks.find_by(number: number))
    return { date: (last_game.to_date + 1).iso8601, anchor_week: number, position: "after" } if last_game

    preview_number = number + 1
    first_game = earliest_game_time_in_week(@season.weeks.find_by(number: preview_number))
    return nil unless first_game

    { date: (first_game.to_date - 1).iso8601, anchor_week: preview_number, position: "before" }
  end

  def latest_game_time_in_week(week)
    return nil unless week

    all_games.filter_map { |game| game.time if game.week_id == week.id }.max
  end

  def earliest_game_time_in_week(week)
    return nil unless week

    all_games.filter_map { |game| game.time if game.week_id == week.id }.min
  end

  def focus_json(primary_week)
    return { instructions: "No matching weeks were found for the requested week_numbers." } unless primary_week

    label = week_label(primary_week[:week])
    primary_has_results = primary_week[:teams].any? { |team| team[:game][:status] == "final" }

    instructions =
      if primary_has_results
        "Focus primary commentary on #{label} below — its results and next-game previews. " \
          "Any earlier weeks included are historical context only, not the main story."
      else
        "#{label} had no games for our coached teams, so the results to break down are in the earlier " \
          "week(s) below — treat those as the main story. #{label} still carries the current standings, " \
          "polls, bowl projections and championship picture, so lean on it for where things stand right now."
      end

    { current_week: primary_week[:week][:number], instructions: instructions }
  end

  def week_label(week)
    return "the Conference Championship" if week[:conference_championship]
    return week[:name] || "the postseason" if week[:post_season]

    "Week #{week[:number]}"
  end

  def coached_college_seasons
    @coached_college_seasons ||= @season.college_seasons
                                         .includes(:college, :coach, { student_seasons: :student }, { signed_recruits: :week })
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

  # The most recent week being reviewed — the one that carries the sections
  # that aren't week-scoped or that should only appear once no matter how
  # many weeks are bundled together: the national Top 25, bowl projections,
  # conference standings, the championship picture, and the (combined)
  # recruiting trail. Reviewing e.g. Week 13 + Week 14 together (Week 14
  # being only Army–Navy) shouldn't produce two standings tables or two
  # poll tables.
  def primary_week_number
    return @primary_week_number if defined?(@primary_week_number)

    resolved = @week_numbers.select { |number| @season.weeks.exists?(number: number) }
    @primary_week_number = resolved.max
  end

  def week_json(number)
    week = @season.weeks.find_by(number: number)
    return nil unless week

    primary = week.number == primary_week_number

    {
      week: {
        id: week.id,
        number: week.number,
        name: week.name,
        conference_championship: week.conference_championship,
        post_season: week.post_season
      },
      teams: coached_college_seasons.map { |cs| team_week_json(cs, week, primary: primary) },
      top_25: primary ? top_25_for_week(week) : [],
      bowl_projections: primary ? bowl_projections_for_week(week) : [],
      coached_matchups: coached_matchups_for_week(week),
      conference_results: conference_results_for_week(week),
      conference_top_25: conference_top_25_for_week(week),
      conference_heisman_watch: conference_heisman_watch_for_week(week),
      conference_standings: primary && week.number >= MIN_WEEK_NUMBER_FOR_SEASON_STATS ? conference_standings_json : nil,
      conference_championships: primary ? conference_championships_json(week) : []
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
  #
  # Scoped to matchups the podcast audience actually cares about: a
  # projection involving one of our coached teams, or any CFP first-round
  # game (the bracket's entry point — worth calling out regardless of who's
  # in it). Later CFP rounds and unrelated bowls are dropped.
  def bowl_projections_for_week(week)
    preview_week = @season.weeks.find_by(number: week.number + 1)
    return [] unless preview_week

    preview_week.bowl_projections
                .includes(:projected_home_college, :projected_away_college)
                .order(:time)
                .select { |bp| relevant_bowl_projection?(bp) }
                .map { |bp| bowl_projection_json(bp) }
  end

  def relevant_bowl_projection?(bp)
    bp.first_round? ||
      coached_college_ids.include?(bp.projected_home_college_id) ||
      coached_college_ids.include?(bp.projected_away_college_id)
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

  def team_week_json(college_season, week, primary:)
    games = games_for_college(college_season.college_id)
    this_week_game = games.find { |game| game.week_id == week.id }
    next_game = games.find { |game| game.week.number > week.number }
    injuries = injury_report_json(college_season, week)
    played_this_week = this_week_game && game_result(this_week_game, college_season.college_id).present?

    {
      college: { id: college_season.college.id, name: college_season.college.name },
      coach: coach_json(college_season.coach),
      record_entering_week: record_before(college_season.college_id, games, week.number),
      ranking: ranking_json(college_season.college_id, week),
      game: this_week_game_json(this_week_game, college_season.college_id),
      top_performers: top_performers_json(this_week_game, college_season),
      players_of_the_week: players_of_the_week_json(college_season, week),
      recruiting_trail: primary ? combined_recruiting_trail_json(college_season) : [],
      injury_report: injuries[:new],
      lingering_injuries: injuries[:lingering],
      next_game: next_game && upcoming_game_json(next_game, college_season.college_id),
      season_outlook: season_outlook_json(college_season, games, week, next_game),
      # Season-to-date numbers only move when the team plays — re-showing an
      # identical block for a week the team was idle (e.g. everyone but
      # Army/Navy in Week 14) is just noise, so gate on an actual result.
      season_stats: played_this_week && week.number >= MIN_WEEK_NUMBER_FOR_SEASON_STATS ? season_stats_json(college_season) : nil
    }
  end

  # nil unless the team's season is genuinely finished: no game scheduled
  # past the reviewed week AND the review as a whole is at/after the
  # regular-season finale (so an un-uploaded late-season schedule mid-year
  # doesn't read as "season over"). Bowl-eligible teams wait on an invite;
  # the rest are done. `projected_bowl` is the most recent projection that
  # names them.
  def season_outlook_json(college_season, games, week, next_game)
    return nil if next_game || primary_week_number.to_i < REGULAR_SEASON_FINAL_WEEK

    record = record_before(college_season.college_id, games, week.number + 1)
    {
      wins: record[:wins],
      losses: record[:losses],
      bowl_eligible: record[:wins] >= BOWL_ELIGIBILITY_WINS,
      projected_bowl: projected_bowl_for(college_season.college_id)
    }
  end

  def projected_bowl_for(college_id)
    projection = latest_bowl_projections.find do |bp|
      bp.projected_home_college_id == college_id || bp.projected_away_college_id == college_id
    end
    return nil unless projection

    home = projection.projected_home_college_id == college_id
    opponent = home ? projection.projected_away_college : projection.projected_home_college
    { bowl_name: projection.bowl_name, cfp_round: projection.cfp_round, home: home, opponent: opponent&.name }
  end

  # The freshest bowl-projection screenshot on record for this season —
  # projections are captured in bunches on a handful of weeks (see
  # BowlProjection), so "most recent week that has any" is the current
  # picture.
  def latest_bowl_projections
    return @latest_bowl_projections if defined?(@latest_bowl_projections)

    week = @season.weeks.where(id: BowlProjection.select(:week_id)).order(number: :desc).first
    @latest_bowl_projections =
      week ? week.bowl_projections.includes(:projected_home_college, :projected_away_college).to_a : []
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

  # Injuries active as of this week (see Injury#active_as_of?), split into
  # ones that happened THIS week — full context (starter/overall/season
  # stats/replacement) for the Injury Report segment — and ones carried over
  # from an earlier week, which already got that treatment in their own
  # episode. Re-running the full segment on a lingering injury is what led
  # the hosts to repeat themselves week after week; the presenter instead
  # folds `lingering` into a one-line mention under Next Up (see
  # SeasonWeeksMarkdownPresenter#next_up_lines). The whole roster is loaded
  # once here (not just the injured players) so each new-injury entry can
  # report depth-chart context without a query per injury.
  def injury_report_json(college_season, week)
    roster = college_season.student_seasons
                           .includes(:student, injuries: { game: :week })
                           .to_a
    active = roster.flat_map(&:injuries).select { |injury| injury.active_as_of?(week) }
    new_this_week, lingering = active.partition { |injury| injury.game.week.number == week.number }

    {
      new: new_this_week.map { |injury| injury_report_entry_json(injury, roster, week) },
      lingering: lingering.map { |injury| lingering_injury_json(injury) }
    }
  end

  def lingering_injury_json(injury)
    student_season = injury.student_season
    {
      name: student_season.student.name,
      position: student_season.position,
      description: injury.description,
      injured_week_number: injury.game.week.number,
      status: injury.out_for_season? ? "out_for_season" : "expected_back_week_#{injury.return_week_number}"
    }
  end

  # "Starter" isn't a stored fact anywhere — the game doesn't expose a depth
  # chart — so we use the same stand-in the rest of the app does (see
  # PortalPreviewSerializer#top_player_at, WinTotals::Calculator): the
  # highest-overall player listed at a position is that position's starter,
  # and the next one down is the replacement. When the injured player is a
  # backup, `replacement` is instead the starter ahead of him, which is the
  # context that matters ("the guy who's actually playing is fine").
  def injury_report_entry_json(injury, roster, week)
    student_season = injury.student_season
    depth = roster.select { |ss| ss.position == student_season.position && ss.overall.present? }
                  .sort_by { |ss| -ss.overall }
    replacement = depth.find { |ss| ss.id != student_season.id }

    {
      name: student_season.student.name,
      position: student_season.position,
      overall: student_season.overall,
      starter: depth.first&.id == student_season.id,
      description: injury.description,
      injured_week_number: injury.game.week.number,
      status: injury.out_for_season? ? "out_for_season" : "expected_back_week_#{injury.return_week_number}",
      season_stats: injured_player_season_stats(student_season, week),
      replacement: replacement && { name: replacement.student.name, overall: replacement.overall }
    }
  end

  # This player's season-to-date box score through `week`, grouped into the
  # same passing/rushing/receiving/defense buckets as everywhere else and
  # aggregated by PlayerStatTotals. Only buckets with real production are
  # kept; nil when the player has no recorded stats yet (e.g. an O-lineman,
  # or someone hurt in week 1) so the presenter can stay silent.
  def injured_player_season_stats(student_season, week)
    rows = StudentGameStat.joins(game: :week)
                          .where(student_season_id: student_season.id)
                          .where(weeks: { number: ..week.number })
                          .to_a
    return nil if rows.empty?

    totals = PlayerStatTotals.call(rows)
    buckets = {
      passing: passing_season_bucket(totals),
      rushing: rushing_season_bucket(totals),
      receiving: receiving_season_bucket(totals),
      defense: defense_season_bucket(totals)
    }.compact
    return nil if buckets.empty?

    { games_played: totals[:games_played] }.merge(buckets)
  end

  def passing_season_bucket(totals)
    return nil unless totals[:passing_attempts].to_i.positive?

    {
      completions: totals[:passing_completions], attempts: totals[:passing_attempts],
      yards: totals[:passing_yards], tds: totals[:passing_tds],
      interceptions: totals[:passing_interceptions], rating: totals[:passing_rating]
    }
  end

  def rushing_season_bucket(totals)
    return nil unless totals[:rushing_carries].to_i.positive?

    {
      carries: totals[:rushing_carries], yards: totals[:rushing_yards],
      avg: totals[:rushing_avg], tds: totals[:rushing_tds]
    }
  end

  def receiving_season_bucket(totals)
    return nil unless totals[:receiving_receptions].to_i.positive?

    {
      receptions: totals[:receiving_receptions], yards: totals[:receiving_yards],
      avg: totals[:receiving_avg], tds: totals[:receiving_tds]
    }
  end

  def defense_season_bucket(totals)
    keys = %i[defense_tackles defense_tfl defense_sacks defense_interceptions]
    return nil unless keys.any? { |key| totals[key].to_f.positive? }

    {
      tackles: totals[:defense_tackles], tfl: totals[:defense_tfl],
      sacks: totals[:defense_sacks], interceptions: totals[:defense_interceptions]
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

  # Recruits first recorded in the week AFTER a reviewed week — the "N+1"
  # convention (week N's episode previews week N+1, so a signing recorded on
  # week N+1 belongs in that episode, mentioned once). When several weeks
  # are reviewed together the preview weeks are combined: reviewing Week 13
  # + Week 14 picks up players inked after Week 13 wrapped (Week 14) and
  # after Week 14 wrapped (Week 15) alike. Rendered only in the primary
  # week's section (see team_week_json) so it isn't repeated. Silent (empty
  # array) when no reviewed week has a preview week with signings.
  def combined_recruiting_trail_json(college_season)
    week_ids = recruiting_preview_week_ids
    return [] if week_ids.empty?

    college_season.signed_recruits
                  .select { |recruit| week_ids.include?(recruit.week_id) }
                  .sort_by { |recruit| [ -(recruit.star_rating || 0), recruit.national_rank || Float::INFINITY, recruit.last_name.to_s ] }
                  .map { |recruit| recruit_json(recruit, college_season) }
  end

  def recruiting_preview_week_ids
    @recruiting_preview_week_ids ||= @week_numbers.filter_map { |number| @season.weeks.find_by(number: number + 1)&.id }
  end

  def recruit_json(recruit, college_season)
    {
      name: recruit.name,
      position: recruit.position,
      transfer: recruit.transfer,
      class_year: recruit.class_year,
      star_rating: recruit.star_rating,
      nil_amount: recruit.nil_amount,
      national_rank: recruit.national_rank,
      position_rank: recruit.position_rank,
      state_rank: recruit.state_rank,
      state: recruit.state,
      roster_context: recruit_roster_context_json(recruit, college_season)
    }
  end

  # EA's recruiting-screen POS codes (read as free text by
  # RecruitmentTrail::Extractor — "LEDG", "REDG", "OT", "ATH"…) use a
  # different vocabulary than roster positions (LE/RE, LT/LG/C/RG/RT), so
  # this bridges a signee to the CollegeSeason::POSITION_GROUPS bucket he
  # slots into. Anything unrecognized (e.g. "ATH") maps to nil and simply
  # gets no roster context.
  RECRUIT_POSITION_GROUPS = {
    "QB" => "Quarterbacks",
    "HB" => "Running Backs", "RB" => "Running Backs", "FB" => "Running Backs",
    "WR" => "Wide Receivers",
    "TE" => "Tight Ends",
    "OT" => "Offensive Line", "OG" => "Offensive Line", "OC" => "Offensive Line", "C" => "Offensive Line",
    "OL" => "Offensive Line", "LT" => "Offensive Line", "RT" => "Offensive Line",
    "LG" => "Offensive Line", "RG" => "Offensive Line",
    "LEDG" => "Defensive Line", "REDG" => "Defensive Line", "EDGE" => "Defensive Line",
    "DE" => "Defensive Line", "DT" => "Defensive Line", "DL" => "Defensive Line",
    "LE" => "Defensive Line", "RE" => "Defensive Line",
    "LOLB" => "Linebackers", "ROLB" => "Linebackers", "MLB" => "Linebackers", "OLB" => "Linebackers",
    "ILB" => "Linebackers", "LB" => "Linebackers", "MIKE" => "Linebackers",
    "WILL" => "Linebackers", "SAM" => "Linebackers",
    "CB" => "Secondary", "FS" => "Secondary", "SS" => "Secondary", "S" => "Secondary", "DB" => "Secondary",
    "K" => "Kickers/Punters", "P" => "Kickers/Punters"
  }.freeze

  # Roster situation at the position group this signee is walking into: how
  # crowded it is, which seniors are graduating out of it (the spot he's
  # most likely "replacing"), how many other signees this class has already
  # added to the same group, and how his NIL number compares to what that
  # group's veterans are paid. nil when the position doesn't map or the team
  # has no scraped roster at that group. "Departing" is graduating seniors
  # only (class_year starting "SR") — it doesn't try to predict
  # underclassmen leaving early or via the portal the way
  # PortalPreviewSerializer does.
  def recruit_roster_context_json(recruit, college_season)
    group = RECRUIT_POSITION_GROUPS[recruit.position.to_s.upcase.strip]
    return nil unless group

    positions = CollegeSeason::POSITION_GROUPS.fetch(group)
    group_players = college_season.student_seasons.select { |ss| positions.include?(ss.position) }
    return nil if group_players.empty?

    seniors = group_players.select { |ss| ss.class_year.to_s.start_with?("SR") }
    returners = group_players - seniors
    group_signees = signees_in_group(college_season, group)

    {
      position_group: group,
      players_in_group: group_players.size,
      returning_next_season: returners.size,
      seniors_departing: seniors.sort_by { |ss| -(ss.overall || 0) }.map { |ss| roster_player_brief(ss) },
      signees_in_group_this_cycle: group_signees.size,
      nil_vs_roster: nil_comparison_hash(recruit.nil_amount, group_players.filter_map(&:nil_amount))
    }
  end

  # Every recruit this college_season has signed this cycle whose position
  # maps into `group` (across all weeks, not just the one being recapped —
  # a signing class spans the whole season).
  def signees_in_group(college_season, group)
    college_season.signed_recruits.select do |sr|
      RECRUIT_POSITION_GROUPS[sr.position.to_s.upcase.strip] == group
    end
  end

  def roster_player_brief(student_season)
    {
      name: student_season.student.name,
      position: student_season.position,
      overall: student_season.overall,
      class_year: student_season.class_year
    }
  end

  # The signee's NIL number against the NIL amounts of the roster veterans
  # in his position group. nil when the signee has no NIL figure or nobody
  # in the group is on record. "all_unpaid" — everyone in the group is on
  # zero NIL, so there's no "going rate" and the presenter handles it
  # separately; otherwise a wide 75–125% band around the average.
  def nil_comparison_hash(recruit_amount, amounts)
    return nil if recruit_amount.nil? || amounts.empty?

    average = (amounts.sum.to_f / amounts.size).round
    {
      recruit: recruit_amount,
      average: average,
      low: amounts.min,
      high: amounts.max,
      standing: nil_standing(recruit_amount, amounts, average)
    }
  end

  def nil_standing(amount, amounts, average)
    return "all_unpaid" if amounts.all?(&:zero?)

    ratio = average.zero? ? 0 : amount.to_f / average
    return "below" if ratio < 0.75
    return "above" if ratio > 1.25

    "in_line"
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

  # The conference-championship matchup for each conference our coached
  # teams play in. CONFIRMED once the Week 15 game is on the schedule
  # (whether or not it's been played) — no more "projected" once the real
  # matchup is known. PROJECTED from standings until then: the two teams
  # with the best conference record right now, tiebroken (in order) by
  # head-to-head, then overall record, then name (see
  # #compare_for_championship_seeding). Only from the Week 11 recap on.
  # Records are derived from played games, not the
  # college_season.conference_wins/losses columns, which lag a gameweek
  # behind (see ConferenceStandings::CommitService).
  def conference_championships_json(week)
    return [] unless week.number > MIN_WEEK_NUMBER_FOR_CHAMPIONSHIP_PROJECTION

    coached_conferences.compact.filter_map do |conference|
      confirmed_conference_championship_json(conference) || projected_conference_championship_json(conference)
    end
  end

  def confirmed_conference_championship_json(conference)
    game = scheduled_conference_championship_game(conference)
    return nil unless game

    finalists = [ game.home_college_id, game.away_college_id ].filter_map { |id| college_seasons_by_college_id[id] }
    {
      conference: conference,
      status: "confirmed",
      teams: finalists.map { |cs| projected_finalist_json(cs, conference_team_record(cs.college_id, conference)) },
      result: championship_result_json(game)
    }
  end

  def championship_result_json(game)
    result = game_result(game, game.home_college_id)
    return nil unless result

    home_won = result[:won]
    {
      winner: (home_won ? game.home_college : game.away_college).name,
      loser: (home_won ? game.away_college : game.home_college).name,
      winner_score: [ result[:team_score], result[:opponent_score] ].max,
      loser_score: [ result[:team_score], result[:opponent_score] ].min
    }
  end

  def scheduled_conference_championship_game(conference)
    week = conference_championship_week
    return nil unless week

    all_games.find do |game|
      game.week_id == week.id &&
        conference_for(game.home_college_id) == conference &&
        conference_for(game.away_college_id) == conference
    end
  end

  def projected_conference_championship_json(conference)
    college_seasons = conference_college_seasons(conference)
    return nil if college_seasons.size < 2

    records = college_seasons.to_h { |cs| [ cs.college_id, conference_team_record(cs.college_id, conference) ] }
    head_to_head = conference_head_to_head(conference)
    seeded = college_seasons.sort { |a, b| compare_for_championship_seeding(a, b, records, head_to_head) }

    {
      conference: conference,
      status: "projected",
      teams: seeded.first(2).map { |cs| projected_finalist_json(cs, records[cs.college_id]) },
      tiebreaker_note: championship_bubble_note(seeded, records, head_to_head)
    }
  end

  def projected_finalist_json(college_season, record)
    {
      college: { id: college_season.college.id, name: college_season.college.name },
      coached_by_us: coached_college_ids.include?(college_season.college_id),
      conference_record: { wins: record[:conference_wins], losses: record[:conference_losses] },
      overall_record: { wins: record[:overall_wins], losses: record[:overall_losses] }
    }
  end

  def conference_college_seasons(conference)
    college_seasons_by_college_id.values.select { |cs| cs.conference == conference }
  end

  # Conference and overall W-L from this team's completed regular-season
  # games (a conference game = both sides in the same conference). Bowl and
  # conference-championship weeks are excluded so this stays a regular-season
  # standings picture.
  def conference_team_record(college_id, conference)
    conference_wins = conference_losses = overall_wins = overall_losses = 0

    regular_season_games_for(college_id).each do |game|
      result = game_result(game, college_id)
      next unless result

      opponent_id = game.home_college_id == college_id ? game.away_college_id : game.home_college_id
      conference_game = conference_for(opponent_id) == conference

      if result[:won]
        overall_wins += 1
        conference_wins += 1 if conference_game
      else
        overall_losses += 1
        conference_losses += 1 if conference_game
      end
    end

    { conference_wins: conference_wins, conference_losses: conference_losses,
      overall_wins: overall_wins, overall_losses: overall_losses }
  end

  def regular_season_games_for(college_id)
    games_for_college(college_id).reject { |game| game.week.post_season || game.week.conference_championship }
  end

  # { [winner_college_id, loser_college_id] => times it happened } across
  # this conference's completed regular-season games.
  def conference_head_to_head(conference)
    outcomes = Hash.new(0)

    all_games.each do |game|
      next if game.week.post_season || game.week.conference_championship
      next unless conference_for(game.home_college_id) == conference && conference_for(game.away_college_id) == conference

      result = game_result(game, game.home_college_id)
      next unless result

      winner_id, loser_id = result[:won] ? [ game.home_college_id, game.away_college_id ] : [ game.away_college_id, game.home_college_id ]
      outcomes[[ winner_id, loser_id ]] += 1
    end

    outcomes
  end

  # Sort comparator implementing the seeding priority the user asked for:
  # conference win pct, then head-to-head, then overall win pct, then name.
  # Head-to-head is only a pairwise signal, so for a 3+ way tie the result
  # can be order-dependent — acceptable here, since anything past "who are
  # the top two" is explicitly don't-care.
  def compare_for_championship_seeding(a, b, records, head_to_head)
    a_record = records[a.college_id]
    b_record = records[b.college_id]

    by_conference = win_pct(b_record[:conference_wins], b_record[:conference_losses]) <=>
                    win_pct(a_record[:conference_wins], a_record[:conference_losses])
    return by_conference unless by_conference.zero?

    by_head_to_head = head_to_head[[ b.college_id, a.college_id ]] <=> head_to_head[[ a.college_id, b.college_id ]]
    return by_head_to_head unless by_head_to_head.zero?

    by_overall = win_pct(b_record[:overall_wins], b_record[:overall_losses]) <=>
                 win_pct(a_record[:overall_wins], a_record[:overall_losses])
    return by_overall unless by_overall.zero?

    a.college.name <=> b.college.name
  end

  # How the #2 seed is holding off the first team out, when the two are
  # level on conference record — the bit of the projection worth explaining
  # on air. nil when the #2/#3 gap isn't actually a tiebreaker.
  def championship_bubble_note(seeded, records, head_to_head)
    return nil if seeded.size < 3

    in_team = seeded[1]
    out_team = seeded[2]
    in_record = records[in_team.college_id]
    out_record = records[out_team.college_id]

    return nil unless in_record[:conference_wins] == out_record[:conference_wins] &&
                      in_record[:conference_losses] == out_record[:conference_losses]

    basis =
      if head_to_head[[ in_team.college_id, out_team.college_id ]] > head_to_head[[ out_team.college_id, in_team.college_id ]]
        "a head-to-head win"
      elsif win_pct(in_record[:overall_wins], in_record[:overall_losses]) >
            win_pct(out_record[:overall_wins], out_record[:overall_losses])
        "a better overall record (#{in_record[:overall_wins]}-#{in_record[:overall_losses]} to " \
          "#{out_record[:overall_wins]}-#{out_record[:overall_losses]})"
      else
        "the tiebreaker"
      end

    "#{in_team.college.name} holds the second spot over #{out_team.college.name} on #{basis}"
  end

  def win_pct(wins, losses)
    total = wins + losses
    total.zero? ? 0.0 : wins.to_f / total
  end

  def conference_championship_week
    return @conference_championship_week if defined?(@conference_championship_week)

    @conference_championship_week = @season.weeks.find_by(conference_championship: true)
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
