class SeasonDashboardSerializer
  # Team-stat columns a committed game is expected to have filled in from
  # its box-score screenshots — the same list GameStats::CommitService
  # whitelists, minus points_in_overtime. OT is legitimately blank on the
  # ~90% of games that don't go to overtime, so it keeps its orange border
  # on the game-update page (a prompt to double-check) but is deliberately
  # ignored here so it doesn't flag every game as "missing" on the dashboard.
  REQUIRED_COLLEGE_STAT_FIELDS = (GameStats::StatFields::COLLEGE_FIELDS - %i[points_in_overtime]).freeze

  def initialize(season)
    @season = season
  end

  def as_json
    teams = coached_college_seasons.map { |cs| team_json(cs) }

    {
      id: @season.id,
      year: @season.year,
      dynasty: { id: @season.dynasty.id, name: @season.dynasty.name },
      teams: teams,
      top_25: top_25_json,
      heisman_watch: heisman_watch_json,
      players_of_the_week: players_of_the_week_json,
      around_the_league: around_the_league_json,
      current_week_number: current_week_number,
      last_played_week_number: last_played_week_number,
      signed_recruits_last_week_number: signed_recruits_last_week_number,
      recruits: recruits_json,
      postseason_recap: postseason_recap_json
    }
  end

  private

  def coached_college_seasons
    @coached_college_seasons ||= @season.college_seasons
                                        .includes(:college, :coach, :student_seasons, :recruiting_season,
                                                  signed_recruits: :week)
                                        .where.not(coach_id: nil)
                                        .joins(:college)
                                        .order("colleges.name")
                                        .to_a
  end

  # The highest week number any coached team has a signed recruit recorded
  # against — drives the Recruitment Trail card's "up to date" badge on the
  # updates page. nil when nothing's been logged yet.
  def signed_recruits_last_week_number
    Week.joins(:signed_recruits)
        .where(season_id: @season.id)
        .where(signed_recruits: { college_season_id: @season.college_seasons.where.not(coach_id: nil).select(:id) })
        .maximum(:number)
  end

  # Every signed recruit (HS/JUCO signees and portal transfers alike) for
  # each coached team this season, grouped by team, best classes' headline
  # names first: star rating desc, then last name. Teams with nothing signed
  # yet are still listed so the card can show them at zero.
  def recruits_json
    coached_college_seasons.map do |college_season|
      recruits = college_season.signed_recruits
                               .sort_by { |sr| [ -(sr.star_rating || 0), sr.last_name.to_s.downcase ] }

      {
        college: { id: college_season.college.id, name: college_season.college.name },
        coach: { id: college_season.coach.id, name: college_season.coach.name },
        recruits: recruits.map { |sr| recruit_json(sr) }
      }
    end
  end

  def recruit_json(signed_recruit)
    {
      id: signed_recruit.id,
      name: signed_recruit.name,
      position: signed_recruit.position,
      star_rating: signed_recruit.star_rating,
      class_year: signed_recruit.class_year,
      transfer: signed_recruit.transfer,
      state: signed_recruit.state,
      national_rank: signed_recruit.national_rank,
      position_rank: signed_recruit.position_rank,
      nil_amount: signed_recruit.nil_amount,
      week: { id: signed_recruit.week.id, number: signed_recruit.week.number, name: signed_recruit.week.name }
    }
  end

  # The dashboard's one time-of-year-dependent card. It surfaces whichever
  # of these three has become available, most-recent stage winning:
  #   1. award winners recorded for this season           -> "awards"
  #   2. else this season has bowl projections on record  -> "bowl_projections"
  #   3. else last season's finished recruiting classes   -> "recruiting_recap"
  # In a dynasty's very first season there's no previous recruiting recap
  # either, so mode 3 just comes back empty.
  def postseason_recap_json
    return { mode: "awards", awards: award_winners_json } if season_award_winners.any?
    return { mode: "bowl_projections", bowl_projections: bowl_projections_json } if dashboard_bowl_projections.any?

    { mode: "recruiting_recap", recruiting_recap: previous_recruiting_recap_json }
  end

  def season_award_winners
    @season_award_winners ||= @season.season_awards
                                     .includes(:award, :coach, student_season: [ :student, { college_season: :college } ])
                                     .sort_by { |season_award| season_award.award.sort_order }
  end

  def award_winners_json
    season_award_winners.map do |season_award|
      student_season = season_award.student_season
      {
        id: season_award.id,
        award: { id: season_award.award.id, name: season_award.award.name },
        recipient_type: season_award.award.recipient_type,
        name: season_award.recipient_name,
        stat_line: season_award.stat_line,
        player: student_season && player_json(student_season).merge(
          college: student_college_json(student_season),
          coached_by_us: coached_by_us?(student_season)
        ),
        coach: season_award.coach && award_coach_json(season_award.coach)
      }
    end
  end

  def award_coach_json(coach)
    college_season = coached_college_seasons.find { |cs| cs.coach_id == coach.id }
    {
      id: coach.id,
      name: coach.name,
      college: college_season && { id: college_season.college.id, name: college_season.college.name },
      coached_by_us: college_season.present?
    }
  end

  # The freshest bowl-projection snapshot on record for this season —
  # projections are captured in bunches on a handful of weeks (see
  # BowlProjection), so "most recent week that has any" is the current
  # picture. Scoped like the broadcast recap: any CFP game (the whole
  # bracket is dashboard-worthy) plus any bowl involving a coached team.
  def latest_bowl_projection_week
    return @latest_bowl_projection_week if defined?(@latest_bowl_projection_week)

    @latest_bowl_projection_week = @season.weeks
                                          .where(id: BowlProjection.select(:week_id))
                                          .order(number: :desc)
                                          .first
  end

  def dashboard_bowl_projections
    return @dashboard_bowl_projections if defined?(@dashboard_bowl_projections)
    return @dashboard_bowl_projections = [] unless latest_bowl_projection_week

    @dashboard_bowl_projections = latest_bowl_projection_week.bowl_projections
                                                            .includes(:projected_home_college, :projected_away_college)
                                                            .select do |bp|
      bp.cfp_round.present? ||
        coached_college_ids.include?(bp.projected_home_college_id) ||
        coached_college_ids.include?(bp.projected_away_college_id)
    end
  end

  def bowl_projections_json
    dashboard_bowl_projections
      .sort_by { |bp| [ bp.cfp_round ? 0 : 1, bp.cfp_round_before_type_cast || 0, bp.time&.to_i || 0, bp.bowl_name ] }
      .map do |bp|
        {
          id: bp.id,
          bowl_name: bp.bowl_name,
          cfp_round: bp.cfp_round,
          home: bowl_projection_side_json(bp.projected_home_college),
          away: bowl_projection_side_json(bp.projected_away_college)
        }
      end
  end

  def bowl_projection_side_json(college)
    return nil unless college

    {
      id: college.id,
      name: college.name,
      rank: rank_for_college(college.id),
      coached_by_us: coached_college_ids.include?(college.id)
    }
  end

  # Last season's final recruiting-class summaries for the teams coached
  # then (rank, points, star breakdown) — the "how did the class I just
  # signed turn out" recap that fills this card until the current season
  # has any postseason data of its own. Empty in a dynasty's first season.
  def previous_recruiting_recap_json
    previous_season = @season.previous_season
    return [] unless previous_season

    previous_season.college_seasons
                   .includes(:college, :coach, :recruiting_season)
                   .where.not(coach_id: nil)
                   .joins(:college)
                   .order("colleges.name")
                   .filter_map do |college_season|
      recruiting_season = college_season.recruiting_season
      next unless recruiting_season

      {
        college: { id: college_season.college.id, name: college_season.college.name },
        coach: college_season.coach && { id: college_season.coach.id, name: college_season.coach.name },
        ranking: recruiting_season.ranking,
        points: recruiting_season.points,
        total_signed: recruiting_season.total_signed,
        nil_spent: recruiting_season.nil_spent,
        five_stars: recruiting_season.five_stars,
        four_stars: recruiting_season.four_stars,
        three_stars: recruiting_season.three_stars,
        two_stars: recruiting_season.two_stars,
        one_stars: recruiting_season.one_stars
      }
    end
  end

  # The most recent week (by number) that actually has rankings/candidates
  # entered — lets the dashboard show "current" league context regardless
  # of how far into the season the data entry has gotten.
  def latest_ranked_week
    return @latest_ranked_week if defined?(@latest_ranked_week)

    @latest_ranked_week = @season.weeks
                                  .joins(:college_week_rankings)
                                  .order(number: :desc)
                                  .first
  end

  # The last 3 weeks (most recent first) that actually have Heisman
  # candidates entered, so the dashboard can show the watch's recent trend
  # rather than just a single snapshot week.
  def recent_heisman_weeks
    return @recent_heisman_weeks if defined?(@recent_heisman_weeks)

    @recent_heisman_weeks = @season.weeks
                                    .joins(:heisman_candidates)
                                    .distinct
                                    .order(number: :desc)
                                    .limit(3)
                                    .includes(heisman_candidates: [ student_season: [ :student, { college_season: :college } ] ])
  end

  # The last 3 weeks (most recent first) that actually have Players of the
  # Week entered, same "recent trend" convention as recent_heisman_weeks.
  def recent_players_of_the_week_weeks
    return @recent_players_of_the_week_weeks if defined?(@recent_players_of_the_week_weeks)

    @recent_players_of_the_week_weeks = @season.weeks
                                                 .joins(:players_of_the_week)
                                                 .distinct
                                                 .order(number: :desc)
                                                 .limit(3)
                                                 .includes(players_of_the_week: [ student_season: [ :student, { college_season: :college } ] ])
  end

  def top_25_json
    return { week: nil, rankings: [] } unless latest_ranked_week

    rankings = latest_ranked_week.college_week_rankings
                                  .includes(:college)
                                  .order(:ranking)
                                  .map { |cwr| top_25_ranking_json(cwr) }

    { week: { id: latest_ranked_week.id, number: latest_ranked_week.number, name: latest_ranked_week.name },
      rankings: rankings }
  end

  def college_seasons_by_college_id
    @college_seasons_by_college_id ||= @season.college_seasons.index_by(&:college_id)
  end

  def top_25_ranking_json(cwr)
    college_season = college_seasons_by_college_id[cwr.college_id]

    {
      rank: cwr.ranking,
      rank_trend: rank_trend(cwr.ranking, previous_rankings_by_college_id[cwr.college_id]),
      college: { id: cwr.college.id, name: cwr.college.name, conference: college_season&.conference },
      coached_by_us: coached_college_ids.include?(cwr.college_id),
      record: college_season && { wins: college_season.wins, losses: college_season.losses },
      this_week: this_week_matchup_json(cwr.college_id),
      last_result: college_season && top_25_last_result_json(college_season)
    }
  end

  # The most recent ranking each currently-ranked college held before
  # latest_ranked_week — skips over any weeks that don't have rankings
  # entered, same "most recently entered" convention as latest_ranked_week
  # itself, so a gap in data entry doesn't read as "unranked last week."
  def previous_rankings_by_college_id
    return @previous_rankings_by_college_id if defined?(@previous_rankings_by_college_id)
    return @previous_rankings_by_college_id = {} unless latest_ranked_week

    rows = CollegeWeekRanking.joins(:week)
                              .where(weeks: { season_id: @season.id })
                              .where("weeks.number < ?", latest_ranked_week.number)
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

  # Every game being played in latest_ranked_week, indexed by each side's
  # college_id — "who's on deck" for a Top 25 team this week.
  def this_week_games_by_college_id
    return @this_week_games_by_college_id if defined?(@this_week_games_by_college_id)
    return @this_week_games_by_college_id = {} unless latest_ranked_week

    games = Game.where(week_id: latest_ranked_week.id).includes(:home_college, :away_college)
    @this_week_games_by_college_id = games.each_with_object({}) do |game, hash|
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

  # The most recent played game through the latest ranked week — "how'd
  # they do last time out."
  def top_25_last_result_json(college_season)
    game = college_season.games
                          .includes(:home_college, :away_college, :college_game_stats, :week)
                          .select { |g| g.week.number <= latest_ranked_week.number && g.played? }
                          .max_by { |g| g.week.number }
    return nil unless game

    stats = game.college_game_stats.index_by(&:college_id)
    team_stat = stats[college_season.college_id]
    opponent_college = game.home_college_id == college_season.college_id ? game.away_college : game.home_college
    opponent_stat = stats[opponent_college.id]
    return nil unless team_stat&.final_score && opponent_stat&.final_score

    {
      opponent: { id: opponent_college.id, name: opponent_college.name, abbrev: opponent_college.abbrev },
      team_score: team_stat.final_score,
      opponent_score: opponent_stat.final_score,
      won: team_stat.final_score > opponent_stat.final_score
    }
  end

  def heisman_watch_json
    heisman_winner = @season.heisman_winner
    winner = heisman_winner && player_json(heisman_winner).merge(
      college: student_college_json(heisman_winner),
      coached_by_us: coached_by_us?(heisman_winner)
    )

    {
      winner: winner,
      weeks: recent_heisman_weeks.map do |week|
        {
          week: { id: week.id, number: week.number, name: week.name },
          candidates: week.heisman_candidates.map { |hc| heisman_candidate_json(hc) }
        }
      end
    }
  end

  # The most recent week (season-wide, any game) that's actually been
  # played — used as a fallback by current_week_number once every
  # week-with-games has fully resolved.
  def last_played_week_number
    return @last_played_week_number if defined?(@last_played_week_number)

    @last_played_week_number = @season.weeks
                                       .includes(games: :college_game_stats)
                                       .select { |week| week.games.any?(&:played?) }
                                       .map(&:number)
                                       .max
  end

  # The week the dashboard defaults to for "Around the League": the
  # earliest week any coached team still has an unplayed game in — i.e.
  # the week the dynasty is actually in the middle of. Scoped to coached
  # teams (rather than "any week with an unplayed game league-wide") so an
  # unrelated, never-simulated slate like other teams' Week 0 openers
  # doesn't get mistaken for "current." Falls back to the last week any
  # coached team played (+1) once every coached team has finished its
  # season, or the season's first week if nothing has been played at all.
  def current_week_number
    return @current_week_number if defined?(@current_week_number)

    next_game_weeks = coached_college_seasons.filter_map do |cs|
      cs.games.includes(:college_game_stats, :week)
        .sort_by { |g| g.week.number }
        .find { |g| !g.played? }
        &.week&.number
    end

    @current_week_number = next_game_weeks.min || (last_played_week_number ? last_played_week_number + 1 : @season.weeks.minimum(:number))
  end

  # Every game NOT involving a coached team, grouped by week — i.e.
  # everything a coach can't already see on one of their own team cards —
  # so the dashboard can show what's happening around the rest of the league.
  # Every week is included (even ones with no non-coached games) so the
  # frontend can scroll to any week, defaulting to current_week_number.
  def around_the_league_json
    @season.weeks
           .order(:number)
           .includes(games: %i[home_college away_college college_game_stats])
           .map do |week|
      games = week.games.reject do |g|
        coached_college_ids.include?(g.home_college_id) || coached_college_ids.include?(g.away_college_id)
      end

      { week: { id: week.id, number: week.number, name: week.name }, games: games.map { |g| league_game_json(g) } }
    end
  end

  def league_game_json(game)
    stats = game.college_game_stats.index_by(&:college_id)
    home_stat = stats[game.home_college_id]
    away_stat = stats[game.away_college_id]
    played = home_stat&.final_score && away_stat&.final_score

    {
      id: game.id,
      time: game.time,
      home: { id: game.home_college.id, name: game.home_college.name, rank: rank_for_college(game.home_college_id) },
      away: { id: game.away_college.id, name: game.away_college.name, rank: rank_for_college(game.away_college_id) },
      result: played ? { home_score: home_stat.final_score, away_score: away_stat.final_score } : nil
    }
  end

  def heisman_candidate_json(candidate)
    student_season = candidate.student_season
    player_json(student_season).merge(
      college: student_college_json(student_season),
      coached_by_us: coached_by_us?(student_season)
    )
  end

  def student_college_json(student_season)
    college = student_season.college_season.college
    { id: college.id, name: college.name, rank: rank_for_college(college.id) }
  end

  # Grouped the same way heisman_watch_json groups candidates by week — the
  # frontend section is meant to look and behave like Heisman Watch, just
  # with up to 4 slots (National/Conference x Offense/Defense) per week
  # instead of one watch list.
  def players_of_the_week_json
    {
      weeks: recent_players_of_the_week_weeks.map do |week|
        {
          week: { id: week.id, number: week.number, name: week.name },
          honorees: sorted_players_of_the_week(week).map { |potw| player_of_the_week_json(potw) }
        }
      end
    }
  end

  # National honorees before conference ones, otherwise preserving whatever
  # order they were entered in (each_with_index tiebreak — sort_by alone
  # isn't guaranteed stable).
  def sorted_players_of_the_week(week)
    week.players_of_the_week
        .each_with_index
        .sort_by { |potw, i| [ potw.national ? 0 : 1, i ] }
        .map(&:first)
  end

  def player_of_the_week_json(potw)
    student_season = potw.student_season

    {
      id: potw.id,
      name: student_season.student.name,
      position: student_season.position,
      side: potw.side,
      national: potw.national,
      conference: potw.conference,
      stat_line: potw.stat_line,
      college: student_college_json(student_season),
      coached_by_us: coached_by_us?(student_season)
    }
  end

  def coached_college_ids
    @coached_college_ids ||= @season.college_seasons.where.not(coach_id: nil).pluck(:college_id).to_set
  end

  def coached_by_us?(student_season)
    coached_college_ids.include?(student_season.college_season.college_id)
  end

  def team_json(college_season)
    season_stats = TeamSeasonStats.new(college_season)
    played_games = season_stats.played_games
    record = effective_record(college_season, played_games)

    {
      id: college_season.id,
      college: {
        id: college_season.college.id,
        name: college_season.college.name,
        alternate_name: college_season.college.alternate_name,
        conference: college_season.conference
      },
      coach: { id: college_season.coach.id, name: college_season.coach.name },
      overall: college_season.overall,
      offense: college_season.offense,
      defense: college_season.defense,
      prestige: college_season.prestige,
      recruiting: recruiting_json(college_season),
      wins: record[:wins],
      losses: record[:losses],
      nil_spend: college_season.nil_spend,
      nil_spend_dollars: nil_spend_dollars(college_season.nil_spend),
      nil_spend_by_position: nil_spend_by_position_json(college_season),
      current_rank: current_rank(college_season),
      next_game: next_game_json(college_season),
      best_offensive_players: college_season.best_offensive_players.map { |ss| player_json(ss) },
      best_defensive_players: college_season.best_defensive_players.map { |ss| player_json(ss) },
      stat_leaders: stat_leaders_json(season_stats.stat_leaders),
      team_stats: season_stats.team_stats,
      team_totals: season_stats.team_totals,
      position_group_averages: college_season.position_group_averages,
      weeks: weeks_json(college_season)
    }
  end

  # NIL spend is tracked in the game's abstract "points"; the broadcast
  # team-breakdown episode converts it to a dollar figure so the podcast
  # script reads naturally, and the dashboard's NIL section shows that same
  # figure — so it reuses that one conversion rather than defining a second.
  def nil_spend_dollars(points)
    return nil if points.blank?

    points * TeamBreakdownSerializer::DOLLARS_PER_NIL_POINT
  end

  # nil_spend_by_position is stored keyed by raw position label ("QB",
  # "K/P", ...). Emitted as an ordered array of {position, points, dollars}
  # rather than a hash so apiClient's camelCase key conversion doesn't
  # mangle labels like "K/P" (same reason NilSpend::Extractor uses an array).
  def nil_spend_by_position_json(college_season)
    by_position = college_season.nil_spend_by_position
    return [] if by_position.blank?

    NilSpend::Extractor::POSITIONS.filter_map do |position|
      points = by_position[position]
      next if points.blank?

      { position: position, points: points, dollars: nil_spend_dollars(points) }
    end
  end

  def recruiting_json(college_season)
    recruiting_season = college_season.recruiting_season
    return nil unless recruiting_season

    {
      ranking: recruiting_season.ranking,
      points: recruiting_season.points,
      total_signed: recruiting_season.total_signed,
      nil_spent: recruiting_season.nil_spent,
      five_stars: recruiting_season.five_stars,
      four_stars: recruiting_season.four_stars,
      three_stars: recruiting_season.three_stars,
      two_stars: recruiting_season.two_stars,
      one_stars: recruiting_season.one_stars
    }
  end

  # college_season.wins/losses is a manually entered snapshot that can lag
  # behind actual results (e.g. a completed game before standings have been
  # re-entered) — use whichever source accounts for more games played, and
  # prefer the stored/official value on a tie.
  def effective_record(college_season, played_games)
    computed_count = played_games.size
    stored_count = college_season.wins.to_i + college_season.losses.to_i
    return { wins: college_season.wins, losses: college_season.losses } if stored_count >= computed_count

    wins = played_games.count { |g| g[:won] }
    { wins: wins, losses: computed_count - wins }
  end

  # Wraps TeamSeasonStats#stat_leaders' { student_season:, value: } shape into
  # this serializer's standard player_json, once it has any recorded game
  # stats — nil until then, so the frontend can keep showing the
  # rating-based best_offensive/defensive_players instead.
  def stat_leaders_json(leaders)
    return nil unless leaders

    leaders.transform_values { |leader| leader && player_json(leader[:student_season]).merge(value: leader[:value]) }
  end

  def current_rank(college_season)
    rank_for_college(college_season.college_id)
  end

  # This week's Top 25 rank for any college (not just coached ones) — used
  # everywhere a team name shows up (schedules, Around the League, Heisman
  # Watch) so a ranked opponent reads as ranked wherever it appears.
  def rank_for_college(college_id)
    return nil unless latest_ranked_week

    latest_ranked_week.college_week_rankings.find { |cwr| cwr.college_id == college_id }&.ranking
  end

  # The next week (in order) where this team has a scheduled game that
  # hasn't been played yet — what a coach checks the dashboard for mid-week.
  # Uses Game#played? (rather than duplicating its "2 stat rows" logic in
  # SQL) since the number of games per team per season is small.
  def next_game_json(college_season)
    upcoming = college_season.games
                              .includes(:home_college, :away_college, :college_game_stats, :week)
                              .sort_by { |g| g.week.number }
                              .find { |g| !g.played? }
    return nil unless upcoming

    opponent_id = upcoming.home_college_id == college_season.college_id ? upcoming.away_college_id : upcoming.home_college_id
    opponent_season = college_seasons_by_college_id[opponent_id]

    {
      week: { id: upcoming.week.id, number: upcoming.week.number, name: upcoming.week.name },
      opponent: opponent_json(upcoming, college_season.college_id),
      active_injury_count: active_injury_count(college_season, upcoming.week),
      opponent_overall: opponent_season&.overall,
      opponent_record: opponent_season && effective_record(opponent_season, TeamSeasonStats.new(opponent_season).played_games),
      opponent_last_result: opponent_season && opponent_last_result_json(opponent_season, upcoming.week.number)
    }
  end

  # What happened for this opponent the single week before before_week_number
  # — not a multi-week backward scan, since the point of this is to surface
  # a gap ("missing") rather than quietly search past it for an older
  # result. A week with no Game is only reported as "bye" if it's in
  # CollegeSeason#bye_week_ids (the only place that fact is ever recorded —
  # see TeamSchedule::CommitService); otherwise it's "missing" — that
  # team's data for that week just hasn't been uploaded yet. nil when
  # before_week_number is the season's first week (nothing came before it).
  def opponent_last_result_json(opponent_season, before_week_number)
    week = @season.weeks.find_by(number: before_week_number - 1)
    return nil unless week

    game = opponent_season.games
                           .includes(:home_college, :away_college, :college_game_stats)
                           .find { |g| g.week_id == week.id }
    result = game && result_json(game, opponent_season.college_id)
    week_json = { id: week.id, number: week.number, name: week.name }

    return { status: "final", week: week_json, opponent: opponent_json(game, opponent_season.college_id), result: result } if result
    return { status: "bye", week: week_json } if opponent_season.bye_week_ids.include?(week.id)

    { status: "missing", week: week_json }
  end

  # How many of this team's players are still banged up heading into their
  # next game — see Injury#active_as_of?.
  def active_injury_count(college_season, week)
    college_season.student_seasons
                   .includes(:student, injuries: { game: :week })
                   .flat_map(&:injuries)
                   .count { |injury| injury.active_as_of?(week) }
  end

  def player_json(student_season)
    return nil unless student_season

    {
      id: student_season.id,
      name: student_season.student.name,
      position: student_season.position,
      overall: student_season.overall,
      dev_trait: student_season.dev_trait,
      class_year: student_season.class_year
    }
  end

  def weeks_json(college_season)
    games_by_week = college_season.games
                                  .includes(:home_college, :away_college, :college_game_stats,
                                            student_game_stats: { student_season: :college_season })
                                  .index_by(&:week_id)

    @season.weeks.order(:number).map do |week|
      game = games_by_week[week.id]
      {
        id: week.id,
        number: week.number,
        name: week.name,
        conference_championship: week.conference_championship,
        post_season: week.post_season,
        game_id: game&.id,
        opponent: opponent_json(game, college_season.college_id),
        result: result_json(game, college_season.college_id),
        missing_stats: missing_stats?(game)
      }
    end
  end

  # Whether a committed game is missing data a coach would want to notice
  # from the dashboard: any required team-stat field blank on either side
  # (OT excluded — see REQUIRED_COLLEGE_STAT_FIELDS), or zero player-stat
  # rows uploaded for either team. Only games that have actually been saved
  # (two CollegeGameStat rows, same bar as Game#played?) are checked; an
  # unplayed or not-yet-entered game isn't "missing", it's just not done.
  # Reads only the already-preloaded associations, so it adds no queries.
  def missing_stats?(game)
    return false unless game

    team_stats = game.college_game_stats
    return false unless team_stats.size == 2
    return true if team_stats.any? { |stat| REQUIRED_COLLEGE_STAT_FIELDS.any? { |field| stat[field].nil? } }

    player_college_ids = game.student_game_stats
                             .map { |sgs| sgs.student_season.college_season.college_id }
                             .to_set
    return true unless player_college_ids.include?(game.home_college_id)
    return true unless player_college_ids.include?(game.away_college_id)

    false
  end

  def opponent_json(game, college_id)
    return nil unless game

    home = game.home_college_id == college_id
    opponent_college = home ? game.away_college : game.home_college
    {
      id: opponent_college.id,
      name: opponent_college.name,
      home: home,
      user_coached: coached_college_ids.include?(opponent_college.id),
      rank: rank_for_college(opponent_college.id)
    }
  end

  def result_json(game, college_id)
    return nil unless game

    stats = game.college_game_stats.index_by(&:college_id)
    team_stat = stats[college_id]
    opponent_stat = stats.values.find { |s| s.college_id != college_id }
    return nil unless team_stat&.final_score && opponent_stat&.final_score

    {
      team_score: team_stat.final_score,
      opponent_score: opponent_stat.final_score,
      won: team_stat.final_score > opponent_stat.final_score
    }
  end
end
