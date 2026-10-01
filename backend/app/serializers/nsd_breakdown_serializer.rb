# "National Signing Day Breakdown" episode: how each coached team's recruiting
# class shaped up, judged on numbers rather than roster strength (ratings
# haven't progressed yet, so Roster Breakdown owns "how good is the room").
# Per team it covers high school signees, portal transfers, and the class as a
# whole (rank, spend, biggest spend, thin positions).
#
# "Last season" comparisons use the roster as it stands now: ratings only move
# at offseason progression, so the current student_seasons ARE last season's
# numbers. Year-over-year class rank/spend comparisons need a prior season on
# record and are simply omitted (nil) until there is one.
#
# High school signee overalls are hand-entered (SignedRecruit#overall) and a
# transfer's comes from his linked previous-roster StudentSeason; either can be
# missing, so averages report how many overalls they were built from and the
# "one to watch" falls back to stars/national rank when no overall exists.
class NsdBreakdownSerializer
  FRESHMAN_CLASS_YEAR = "FR".freeze

  # The game tracks NIL as abstract points; Roster Breakdown converts them to
  # dollars for the broadcast and so does this export, via the same constant.
  DOLLARS_PER_NIL_POINT = TeamBreakdownSerializer::DOLLARS_PER_NIL_POINT

  # Kickers/punters are neither, so they're never picked as the top offensive
  # or defensive recruit.
  OFFENSE_GROUPS = [ "Quarterbacks", "Backfield", "Wide Receivers/Tight Ends", "Offensive Line" ].freeze
  DEFENSE_GROUPS = [ "Defensive Line", "Linebackers", "Secondary" ].freeze

  def initialize(season)
    @season = season
  end

  def as_json
    teams = coached_college_seasons.map { |cs| team_json(cs) }

    {
      focus: focus_json,
      season: { id: @season.id, year: @season.year, dynasty: @season.dynasty.name },
      teams: teams,
      class_comparison: class_comparison_json(teams),
      data_coverage: data_coverage_json(teams)
    }
  end

  private

  def focus_json
    {
      instructions: "National Signing Day Breakdown for our #{coached_college_seasons.size} coached teams — " \
                    "how each recruiting class shaped up: the high school signees, the portal transfers, where " \
                    "the class ranks nationally and in the conference, what was spent, and which positions are " \
                    "still below the minimum. This is about the recruiting numbers, NOT how strong the roster is " \
                    "— ratings haven't progressed yet. The episode closes with the hosts debating and ranking " \
                    "our teams' classes from worst to best using the numbers."
    }
  end

  def coached_college_seasons
    # preload (not includes): ordering by colleges.name would otherwise turn
    # this into one JOIN across student_seasons x signed_recruits x
    # portal_statuses, a huge cartesian product.
    @coached_college_seasons ||= @season.college_seasons
                                         .preload(:college, :coach, :recruiting_season, :portal_statuses,
                                                  student_seasons: :student, signed_recruits: :student)
                                         .where.not(coach_id: nil)
                                         .joins(:college)
                                         .order("colleges.name")
                                         .to_a
  end

  def conference_peers(conference)
    @conference_peers ||= @season.college_seasons.includes(:college, :recruiting_season).group_by(&:conference)
    @conference_peers.fetch(conference, [])
  end

  # student_id => this season's StudentSeason (with its college), for linked
  # transfers: gives both the overall they bring in and the school they left.
  def transfer_seasons
    @transfer_seasons ||= begin
      student_ids = coached_college_seasons.flat_map(&:signed_recruits).select(&:transfer).filter_map(&:student_id)
      StudentSeason.where(college_season_id: @season.college_seasons.select(:id), student_id: student_ids)
                   .includes(college_season: :college).index_by(&:student_id)
    end
  end

  def dollars(points)
    points && points * DOLLARS_PER_NIL_POINT
  end

  def previous_season
    return @previous_season if defined?(@previous_season)

    @previous_season = @season.dynasty.seasons.find_by(year: @season.year - 1)
  end

  def team_json(college_season)
    signees = college_season.signed_recruits.map { |sr| signee_json(sr) }

    {
      college: { id: college_season.college.id, name: college_season.college.name, conference: college_season.conference },
      coach: { id: college_season.coach.id, name: college_season.coach.name },
      total_signed: signees.size,
      signees: signees.sort_by { |s| [ -(s[:overall] || 0), -s[:star_rating].to_i ] },
      high_school: high_school_json(college_season, signees.select { |s| s[:type] == "high_school" }),
      juco_signed: signees.count { |s| s[:type] == "juco" },
      players_to_watch: players_to_watch_json(signees),
      transfers: transfers_json(college_season, signees.select { |s| s[:type] == "transfer" }),
      overall: overall_json(college_season, signees)
    }
  end

  def signee_json(recruit)
    previous = recruit.transfer ? transfer_seasons[recruit.student_id] : nil
    overall = recruit.transfer ? previous&.overall : recruit.overall
    {
      name: recruit.name,
      position: recruit.position,
      group: RosterNeeds.group_for(recruit.position),
      type: signee_type(recruit),
      star_rating: recruit.star_rating,
      overall: overall,
      class_year: displayed_class_year(recruit),
      from_college: previous&.college_season&.college&.name,
      national_rank: recruit.national_rank,
      nil_dollars: dollars(recruit.nil_amount.to_i)
    }
  end

  # A transfer's CLASS column reads "TR (JR)"; only the "JR" is interesting.
  def displayed_class_year(recruit)
    recruit.class_year.to_s[/\(([^)]+)\)/, 1] || recruit.class_year
  end

  def signee_type(recruit)
    return "transfer" if recruit.transfer

    recruit.class_year.to_s.start_with?("JC") ? "juco" : "high_school"
  end

  # ---- high school ---------------------------------------------------------

  def high_school_json(college_season, signees)
    freshmen = college_season.student_seasons.select { |ss| ss.class_year == FRESHMAN_CLASS_YEAR && ss.overall }
    average = average_of(signees.filter_map { |s| s[:overall] })
    freshman_average = average_of(freshmen.map(&:overall))

    {
      signed: signees.size,
      star_counts: (1..5).to_h { |stars| [ stars, signees.count { |s| s[:star_rating] == stars } ] },
      average_overall: average,
      overalls_entered: signees.count { |s| s[:overall] },
      last_season_freshman_average: freshman_average,
      last_season_freshman_count: freshmen.size,
      difference_vs_freshmen: average && freshman_average && (average - freshman_average).round(1)
    }
  end

  # ---- transfers -----------------------------------------------------------

  def transfers_json(college_season, signees)
    roster = college_season.student_seasons.filter_map(&:overall)
    average = average_of(signees.filter_map { |s| s[:overall] })
    team_average = average_of(roster)

    {
      signed: signees.size,
      average_overall: average,
      overalls_found: signees.count { |s| s[:overall] },
      last_season_team_average: team_average,
      difference_vs_team: average && team_average && (average - team_average).round(1)
    }
  end

  # The team's headline signees: best high school signee, best transfer, and
  # the best on each side of the ball (either kind of signee). Highest overall
  # wins; a high school pick with no overall to go on falls back to the
  # best-rated prospect (stars, then national rank) and `basis` says so. Side
  # of the ball picks need an overall, so they're nil when nothing is rated.
  def players_to_watch_json(signees)
    {
      high_school: pick(signees.select { |s| s[:type] == "high_school" }, stars_fallback: true),
      transfer: pick(signees.select { |s| s[:type] == "transfer" }, stars_fallback: true),
      offense: pick(signees.select { |s| OFFENSE_GROUPS.include?(s[:group]) }),
      defense: pick(signees.select { |s| DEFENSE_GROUPS.include?(s[:group]) })
    }
  end

  def pick(signees, stars_fallback: false)
    rated = signees.select { |s| s[:overall] }
    best = rated.max_by { |s| s[:overall] }
    basis = "overall"
    if best.nil? && stars_fallback && signees.any?
      best = signees.max_by { |s| [ s[:star_rating].to_i, -(s[:national_rank] || 9_999) ] }
      basis = "stars"
    end
    best&.slice(:name, :position, :type, :star_rating, :class_year, :from_college, :overall, :national_rank)&.merge(basis: basis)
  end

  def average_of(values)
    values.empty? ? nil : (values.sum.to_f / values.size).round(1)
  end

  # ---- the class as a whole ------------------------------------------------

  def overall_json(college_season, signees)
    recruiting = college_season.recruiting_season
    {
      average_overall: average_of(signees.filter_map { |s| s[:overall] }),
      value: value_json(college_season, signees),
      national_ranking: recruiting&.ranking,
      ranking_vs_conference: ranking_comparison(college_season),
      last_year_ranking: previous_recruiting(college_season)&.ranking,
      spend: spend_json(college_season, signees),
      biggest_spend: biggest_spend(signees),
      positions_of_worry: positions_of_worry(college_season, signees)
    }
  end

  # Value for money: dollars spent on the class divided by the overall points
  # it brought in (the sum of every signee's overall), so a lower number means
  # more rating per dollar. Built only from signees that have an overall, and
  # `signees_counted` says how many that was, because a class with missing
  # overalls would otherwise look cheaper than it really was.
  def value_json(college_season, signees)
    rated = signees.select { |s| s[:overall] }
    points = rated.sum { |s| s[:overall] }
    spent = spent_dollars(college_season, signees)
    {
      dollars_per_overall_point: points.zero? ? nil : (spent.to_f / points).round,
      overall_points: points,
      signees_counted: rated.size
    }
  end

  # The league-wide recruiting upload when we have it (directly comparable to
  # peers), otherwise the sum over our own signees.
  def spent_dollars(college_season, signees)
    dollars(college_season.recruiting_season&.nil_spent) || signees.sum { |s| s[:nil_dollars].to_i }
  end

  def ranking_comparison(college_season)
    ranked = conference_peers(college_season.conference).select { |cs| cs.recruiting_season&.ranking }
                                                       .sort_by { |cs| cs.recruiting_season.ranking }
    return nil if ranked.empty? || college_season.recruiting_season&.ranking.nil?

    best = ranked.first
    {
      conference: college_season.conference,
      teams_ranked: ranked.size,
      conference_rank: ranked.index { |cs| cs.id == college_season.id } + 1,
      best_in_conference: { college: best.college.name, national_ranking: best.recruiting_season.ranking }
    }
  end

  def spend_json(college_season, signees)
    spent = spent_dollars(college_season, signees)
    peers = conference_peers(college_season.conference).filter_map { |cs| dollars(cs.recruiting_season&.nil_spent) }
    {
      nil_spent: spent,
      conference_average: average_of(peers)&.round,
      conference_rank: peers.empty? ? nil : peers.count { |amount| amount > spent } + 1,
      conference_teams_compared: peers.size,
      last_year: dollars(previous_recruiting(college_season)&.nil_spent)
    }
  end

  def previous_recruiting(college_season)
    return nil unless previous_season

    previous_season.college_seasons.find_by(college_id: college_season.college_id)&.recruiting_season
  end

  def biggest_spend(signees)
    top = signees.max_by { |s| s[:nil_dollars].to_i }
    top && top[:nil_dollars].to_i.positive? ? top.slice(:name, :position, :type, :star_rating, :class_year, :from_college, :overall, :nil_dollars) : nil
  end

  # Groups still under their depth minimum once everyone leaving is gone and
  # this class is counted. Without portal data nobody is known to be leaving,
  # so those teams are flagged in data_coverage rather than trusted here.
  def positions_of_worry(college_season, signees)
    statuses = college_season.portal_statuses.index_by(&:student_season_id)
    RosterNeeds::DEPTH_GROUPS.filter_map do |group, config|
      remaining = college_season.student_seasons.count do |ss|
        config[:positions].include?(ss.position) && !RosterNeeds.leaving?(statuses[ss.id])
      end
      projected = remaining + signees.count { |s| s[:group] == group }
      next if projected >= config[:min_depth]

      { position_group: group, projected_depth: projected, minimum: config[:min_depth], short_by: config[:min_depth] - projected }
    end
  end

  # ---- cross-team ------------------------------------------------------------

  # Side-by-side numbers for the closing debate. Deliberately NOT sorted by
  # any measure (alphabetical) and carries no verdict: the hosts decide the
  # order from the evidence, so handing them a ranking would just have them
  # read it back.
  def class_comparison_json(teams)
    teams.sort_by { |t| t[:college][:name] }.map do |t|
      {
        college: t[:college],
        national_ranking: t[:overall][:national_ranking],
        conference_rank: t[:overall][:ranking_vs_conference]&.dig(:conference_rank),
        total_signed: t[:total_signed],
        high_school_signed: t[:high_school][:signed],
        transfers_signed: t[:transfers][:signed],
        average_overall: t[:overall][:average_overall],
        nil_spent: t[:overall][:spend][:nil_spent],
        dollars_per_overall_point: t[:overall][:value][:dollars_per_overall_point],
        positions_of_worry: t[:overall][:positions_of_worry].map { |w| w[:position_group] }
      }
    end
  end

  def data_coverage_json(teams)
    {
      teams_without_signees: teams.select { |t| t[:total_signed].zero? }.map { |t| t[:college][:name] },
      teams_without_portal_data: coached_college_seasons.select { |cs| cs.portal_statuses.empty? }.map { |cs| cs.college.name },
      teams_without_class_ranking: teams.select { |t| t[:overall][:national_ranking].nil? }.map { |t| t[:college][:name] },
      high_school_without_overall: teams.sum { |t| t[:high_school][:signed] - t[:high_school][:overalls_entered] },
      transfers_without_overall: teams.sum { |t| t[:transfers][:signed] - t[:transfers][:overalls_found] },
      last_year_comparisons_available: previous_season.present?
    }
  end
end
