# The facts behind the season opener's "Something to Prove" segment: for each coached team on the opening card, how
# last season actually went, built so the hosts can name the ONE thing each team has to fix or show. Every number
# says what it was ranked against:
#   - scoring ranks use the conference standings upload, which covers nearly every school, so they are national
#   - yardage ranks use the Team Stats upload, which only some conferences have, so they are ranked only within the
#     team's own conference that season, and only when most of that conference has them
# Facts only: the serializer picks no "weakness" itself, the hosts do.
class SomethingToProveSerializer
  # Fewest teams with season totals that make a conference ranking worth quoting.
  MIN_CONFERENCE_TEAMS = 8
  # A loss by this many points or fewer is a one-score loss.
  ONE_SCORE = 8
  # A current roster with fewer players than this hasn't been imported yet, so nobody can be called gone.
  MIN_ROSTER = 40

  OFFENSE = {
    pass_yards_per_game: ->(cs, g) { cs.passing_yards.to_f / g },
    rush_yards_per_game: ->(cs, g) { cs.rushing_yards.to_f / g },
    total_yards_per_game: ->(cs, g) { cs.total_offensive_yards.to_f / g },
    yards_per_play: ->(cs, _) { cs.yards_per_play.to_f },
    pass_tds_per_game: ->(cs, g) { cs.passing_touchdowns.to_f / g }
  }.freeze
  DEFENSE = {
    total_yards_allowed_per_game: ->(cs, g) { cs.total_yards_allowed.to_f / g },
    pass_yards_allowed_per_game: ->(cs, g) { cs.passing_yards_allowed.to_f / g },
    rush_yards_allowed_per_game: ->(cs, g) { cs.rushing_yards_allowed.to_f / g },
    sacks_per_game: ->(cs, g) { cs.defensive_sacks.to_f / g }
  }.freeze
  LOWER_IS_BETTER = %i[total_yards_allowed_per_game pass_yards_allowed_per_game rush_yards_allowed_per_game].freeze

  def initialize(season, college_ids)
    @season = season
    @college_ids = college_ids
    @previous = season.dynasty.seasons.find_by(year: season.year - 1)
  end

  def as_json(*)
    { year: @season.year, previous_year: @previous&.year, teams: teams }
  end

  private

  def teams
    return [] unless @previous

    @college_ids.filter_map do |college_id|
      current = @season.college_seasons.includes(:college, :coach).find_by(college_id: college_id)
      previous = @previous.college_seasons.find_by(college_id: college_id)
      team_json(current, previous) if current && previous && played(previous).positive?
    end
  end

  def team_json(current, previous)
    {
      college: current.college.name, coach: current.coach&.name,
      new_conference_from: (previous.conference if previous.conference != current.conference),
      conference_last_season: previous.conference, conference_now: current.conference,
      division: division(current, previous),
      record: { wins: previous.wins, losses: previous.losses },
      scoring: scoring(previous),
      losses: losses(previous),
      conference_stats: conference_stats(previous),
      departed: departed(current, previous)
    }
  end

  # Only for a conference that has divisions this season. A team that stayed in its division is just named in it; one that
  # moved says where from (nil for a team new to the conference, whose old league's divisions mean nothing here).
  def division(current, previous)
    return nil if current.division.blank?

    divisions = @season.college_seasons.where(conference: current.conference).where.not(division: [ nil, "" ]).distinct.pluck(:division)
    return nil if divisions.size < 2

    moved = previous.conference == current.conference && previous.division.present? && previous.division != current.division
    { name: current.division, moved_from: (previous.division if moved),
      mates: @season.college_seasons.includes(:college).where(conference: current.conference, division: current.division)
                    .where.not(id: current.id).map { |cs| cs.college.name }.sort }
  end

  def played(college_season) = college_season.wins.to_i + college_season.losses.to_i

  def standings_pool
    @standings_pool ||= @previous.college_seasons.select { |cs| cs.points_for && cs.points_against && played(cs).positive? }
  end

  # Points scored and allowed a game, with the national rank (1 = best) among every school that has standings.
  def scoring(previous)
    return nil unless standings_pool.include?(previous)

    scored = ->(cs) { cs.points_for.to_f / played(cs) }
    allowed = ->(cs) { cs.points_against.to_f / played(cs) }
    {
      points_scored_per_game: scored.call(previous).round(1),
      points_scored_rank: standings_pool.count { |cs| scored.call(cs) > scored.call(previous) } + 1,
      points_allowed_per_game: allowed.call(previous).round(1),
      points_allowed_rank: standings_pool.count { |cs| allowed.call(cs) < allowed.call(previous) } + 1,
      of: standings_pool.size
    }
  end

  def losses(previous)
    games = Game.where(week_id: @previous.week_ids)
                .where("home_college_id = :id OR away_college_id = :id", id: previous.college_id)
                .includes(:college_game_stats, :home_college, :away_college, :week)
    games.filter_map do |game|
      scores = game.college_game_stats.index_by(&:college_id)
      mine = scores[previous.college_id]&.final_score
      opponent_id = game.home_college_id == previous.college_id ? game.away_college_id : game.home_college_id
      theirs = scores[opponent_id]&.final_score
      next unless mine && theirs && mine < theirs

      { opponent: (game.home_college_id == previous.college_id ? game.away_college : game.home_college).name,
        score: "#{mine}-#{theirs}", margin: theirs - mine, one_score: theirs - mine <= ONE_SCORE,
        site: neutral_site?(game) ? "neutral site" : (game.home_college_id == previous.college_id ? "home" : "away"),
        week: game.week.number }
    end.sort_by { |loss| loss[:week] }
  end

  # Same rule as BigGameBreakdownSerializer: only the regular season and the CFP first round have a home team.
  def neutral_site?(game)
    game.week.conference_championship || (game.week.post_season && game.cfp_round != "first_round")
  end

  # Season-total ranks among the team's own conference that year, 1 = best. nil unless it has totals and enough of its
  # conference does too.
  def conference_stats(previous)
    pool = @previous.college_seasons.select { |cs| cs.conference == previous.conference && cs.passing_yards && cs.passing_yards_allowed && played(cs).positive? }
    return nil unless pool.include?(previous) && pool.size >= MIN_CONFERENCE_TEAMS

    stats = OFFENSE.merge(DEFENSE).map do |name, fn|
      value = fn.call(previous, played(previous))
      better = pool.count do |cs|
        other = fn.call(cs, played(cs))
        LOWER_IS_BETTER.include?(name) ? other < value : other > value
      end
      [ name, { value: value.round(name == :yards_per_play ? 1 : name == :pass_tds_per_game ? 2 : 1), rank: better + 1 } ]
    end
    { conference: previous.conference, of: pool.size, stats: stats.to_h }
  end

  # The top rusher and passer from last season who are no longer on the roster (graduated or gone).
  def departed(current, previous)
    on_roster = current.student_seasons.pluck(:student_id).to_set
    return {} if on_roster.size < MIN_ROSTER

    { rusher: top_gone(previous, :rushing_yards, on_roster), passer: top_gone(previous, :passing_yards, on_roster) }.compact
  end

  def top_gone(previous, column, on_roster)
    student_id, total = StudentGameStat.joins(:student_season).where(student_seasons: { college_season_id: previous.id })
                                       .group("student_seasons.student_id").sum(column).max_by { |_, sum| sum.to_i }
    return nil if student_id.nil? || total.to_i.zero? || on_roster.include?(student_id)

    { name: Student.find(student_id).name, yards: total.to_i }
  end
end
