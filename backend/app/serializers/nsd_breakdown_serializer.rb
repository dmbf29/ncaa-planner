# "National Signing Day Breakdown" episode: judges how each coached team
# RECRUITED, not how good the roster is (that's Roster Breakdown's job, and
# ratings haven't progressed yet anyway). The question is "did the class
# answer the needs?", so for every position group it sets what the team
# lost (PortalStatus rows, same definition of "leaving" as Portal Preview)
# against who signed (SignedRecruit rows), and grades the response.
#
# Grading is about filling gaps, not about how good the signees are —
# quality is a later conversation. A group's need is the larger of the
# starters it lost (RosterNeeds::STARTER_SLOTS) and the bodies it's short of
# its depth target once everyone leaving is gone; a signee at the position
# fills one spot no matter his stars or overall. Stars, overall (entered for
# high school/JUCO, or read from a transfer's previous-roster StudentSeason
# with no progression applied) and national rank travel along as context for
# the hosts only.
#
# Coverage grades per group (only groups with a need get one):
#  - addressed: signed at least as many players as the need
#  - patched: signed someone, but fewer than the need
#  - ignored: a real need and nobody signed at the position
# `overstocked` is separate: three or more signees beyond the need.
class NsdBreakdownSerializer
  OVERSTOCK_MARGIN = 3
  COVERAGE_CREDIT = { "addressed" => 1.0, "patched" => 0.5, "ignored" => 0.0 }.freeze

  def initialize(season)
    @season = season
  end

  def as_json
    teams = coached_college_seasons.map { |cs| team_json(cs) }

    {
      focus: focus_json,
      season: { id: @season.id, year: @season.year, dynasty: @season.dynasty.name },
      teams: teams,
      repair_ranking: repair_ranking_json(teams),
      data_coverage: data_coverage_json(teams)
    }
  end

  private

  def focus_json
    {
      instructions: "National Signing Day Breakdown for our #{coached_college_seasons.size} coached teams — " \
                    "a look at how each coach recruited: whether the class answered the roster's needs (who " \
                    "left versus who signed, position by position), where the class ranks nationally and " \
                    "against the rest of the conference, the biggest signing, and the biggest hole left open. " \
                    "This is about the recruiting decisions, NOT how good the roster is — ratings haven't " \
                    "progressed yet, so don't talk about how strong a position group is now. Each team's " \
                    "segment ends with both hosts giving a pit-crew verdict, and the episode closes with the " \
                    "hosts ranking our teams' offseason repair jobs."
    }
  end

  def coached_college_seasons
    @coached_college_seasons ||= @season.college_seasons
                                         .includes(:college, :coach, :recruiting_season, :portal_statuses,
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

  # student_id => overall this season, for linked transfers.
  def transfer_overalls
    @transfer_overalls ||= begin
      student_ids = coached_college_seasons.flat_map(&:signed_recruits).select(&:transfer).filter_map(&:student_id)
      StudentSeason.where(college_season_id: @season.college_seasons.select(:id), student_id: student_ids)
                   .pluck(:student_id, :overall).to_h
    end
  end

  def team_json(college_season)
    signees = college_season.signed_recruits.map { |sr| signee_json(sr) }
    groups = RosterNeeds::DEPTH_GROUPS.keys.map { |group| group_json(college_season, group, signees) }
    needs = groups.select { |g| g[:coverage] }

    {
      college: { id: college_season.college.id, name: college_season.college.name, conference: college_season.conference },
      coach: { id: college_season.coach.id, name: college_season.coach.name },
      class_summary: class_summary_json(college_season, signees),
      position_scorecard: groups,
      needs_summary: needs_summary_json(needs, signees),
      splash_signing: splash_json(signees),
      biggest_hole: biggest_hole_json(needs),
      roster_math: roster_math_json(college_season)
    }
  end

  def signee_json(recruit)
    overall = recruit.transfer ? transfer_overalls[recruit.student_id] : recruit.overall
    {
      name: recruit.name,
      position: recruit.position,
      group: RosterNeeds.group_for(recruit.position),
      type: signee_type(recruit),
      star_rating: recruit.star_rating,
      overall: overall,
      overall_source: overall && (recruit.transfer ? "previous roster" : "entered"),
      national_rank: recruit.national_rank,
      state: recruit.state,
      nil_amount: recruit.nil_amount,
      transfer_linked: recruit.transfer ? recruit.student_id.present? : nil
    }
  end

  def signee_type(recruit)
    return "transfer" if recruit.transfer

    recruit.class_year.to_s.start_with?("JC") ? "juco" : "high_school"
  end

  # ---- class level -------------------------------------------------------

  def class_summary_json(college_season, signees)
    recruiting = college_season.recruiting_season
    {
      total_signed: signees.size,
      high_school: signees.count { |s| s[:type] == "high_school" },
      juco: signees.count { |s| s[:type] == "juco" },
      transfers: signees.count { |s| s[:type] == "transfer" },
      star_counts: star_counts(signees),
      average_stars: average_stars(signees),
      nil_committed: signees.sum { |s| s[:nil_amount].to_i },
      national: recruiting && national_json(recruiting),
      conference_comparison: conference_comparison_json(college_season)
    }
  end

  def star_counts(signees)
    (1..5).to_h { |stars| [ stars, signees.count { |s| s[:star_rating] == stars } ] }
  end

  def average_stars(signees)
    rated = signees.filter_map { |s| s[:star_rating] }
    rated.empty? ? nil : (rated.sum.to_f / rated.size).round(2)
  end

  def national_json(recruiting)
    {
      ranking: recruiting.ranking,
      points: recruiting.points,
      total_signed: recruiting.total_signed,
      nil_spent: recruiting.nil_spent,
      five_stars: recruiting.five_stars,
      four_stars: recruiting.four_stars,
      three_stars: recruiting.three_stars
    }
  end

  # Where this class ranks among the conference's classes, by national
  # ranking from the league-wide recruiting rankings upload. Peers without
  # a ranking (data not uploaded) are left out and `teams_ranked` says how
  # many were actually compared.
  def conference_comparison_json(college_season)
    ranked = conference_peers(college_season.conference).select { |cs| cs.recruiting_season&.ranking }
                                                       .sort_by { |cs| cs.recruiting_season.ranking }
    return nil if ranked.empty? || college_season.recruiting_season&.ranking.nil?

    {
      conference: college_season.conference,
      teams_ranked: ranked.size,
      conference_rank: ranked.index { |cs| cs.id == college_season.id }&.+(1),
      standings: ranked.first(8).map do |cs|
        { college: cs.college.name, national_ranking: cs.recruiting_season.ranking, points: cs.recruiting_season.points, ours: cs.coach_id.present? }
      end
    }
  end

  # ---- position groups ---------------------------------------------------

  def group_json(college_season, group, all_signees)
    config = RosterNeeds::DEPTH_GROUPS[group]
    slots = RosterNeeds::STARTER_SLOTS[group]
    roster = group_roster(college_season, config[:positions])
    remaining = roster.reject { |entry| entry[:leaving] }
    lost = roster.select { |entry| entry[:leaving] }
    starters_lost = lost.select { |entry| roster.first(slots).include?(entry) }
    need = [ starters_lost.size, [ config[:min_depth] - remaining.size, 0 ].max ].max
    signees = all_signees.select { |s| s[:group] == group }

    {
      position_group: group,
      need: need,
      lost: lost.map { |entry| entry.slice(:name, :position, :overall, :status) },
      starters_lost: starters_lost.map { |entry| entry.slice(:name, :position, :overall, :status) },
      remaining_depth: remaining.size,
      min_healthy_depth: config[:min_depth],
      signees: signees,
      coverage: coverage(need, signees),
      overstocked: signees.size - need >= OVERSTOCK_MARGIN
    }
  end

  # Everyone the team had at the group before the offseason (matched
  # roster players plus unmatched portal rows, which still carry their own
  # position and overall), best overall first so the first STARTER_SLOTS
  # entries are the starters.
  def group_roster(college_season, positions)
    statuses = college_season.portal_statuses.index_by(&:student_season_id)
    matched = college_season.student_seasons.select { |ss| positions.include?(ss.position) }.map do |ss|
      status = statuses[ss.id]
      { name: ss.student.name, position: ss.position, overall: ss.overall || 0, leaving: RosterNeeds.leaving?(status), status: status&.status }
    end
    unmatched = college_season.portal_statuses.select { |ps| ps.student_season_id.nil? && positions.include?(PositionBoardMapping.canonical(ps.position)) }.map do |ps|
      { name: ps.display_name, position: ps.position, overall: ps.overall || 0, leaving: RosterNeeds.leaving?(ps), status: ps.status }
    end
    (matched + unmatched).sort_by { |entry| -entry[:overall] }
  end

  # nil when the group has no need at all (nobody starting lost, depth fine).
  def coverage(need, signees)
    return nil if need.zero?
    return "ignored" if signees.empty?

    signees.size >= need ? "addressed" : "patched"
  end

  def needs_summary_json(needs, signees)
    addressed = needs.count { |g| g[:coverage] == "addressed" }
    weights = needs.map { |g| g[:need] }
    credit = needs.zip(weights).sum { |g, weight| COVERAGE_CREDIT[g[:coverage]] * weight }
    {
      groups_with_needs: needs.size,
      addressed: addressed,
      patched: needs.count { |g| g[:coverage] == "patched" },
      ignored: needs.count { |g| g[:coverage] == "ignored" },
      repair_score: weights.sum.zero? || signees.empty? ? nil : (100 * credit / weights.sum).round
    }
  end

  def splash_json(signees)
    return nil if signees.empty?

    best = signees.max_by { |s| [ s[:star_rating].to_i, s[:overall].to_i, -(s[:national_rank] || 9_999) ] }
    priciest = signees.max_by { |s| s[:nil_amount].to_i }
    {
      best_signee: best.slice(:name, :position, :type, :star_rating, :overall, :national_rank, :nil_amount),
      biggest_nil_investment: priciest[:nil_amount].to_i.positive? ? priciest.slice(:name, :position, :type, :star_rating, :overall, :nil_amount) : nil
    }
  end

  # The open need that cost the most: ignored before patched, then by how
  # many starters walked out.
  def biggest_hole_json(needs)
    open = needs.select { |g| %w[ignored patched].include?(g[:coverage]) }
    hole = open.max_by { |g| [ g[:coverage] == "ignored" ? 1 : 0, g[:starters_lost].size ] }
    hole && hole.slice(:position_group, :coverage, :starters_lost, :remaining_depth, :min_healthy_depth)
  end

  def roster_math_json(college_season)
    RosterNeeds.roster_math(
      college_season,
      roster_size: college_season.student_seasons.size,
      departures: college_season.portal_statuses.count { |ps| RosterNeeds.leaving?(ps) }
    )
  end

  # ---- cross-team --------------------------------------------------------

  # Best repair job first, by repair_score — a data backstop for the closing
  # segment; the hosts render the actual verdict and may disagree. Teams
  # with no scored needs sort last.
  def repair_ranking_json(teams)
    teams.sort_by { |t| -(t[:needs_summary][:repair_score] || -1) }.map do |t|
      {
        college: t[:college],
        repair_score: t[:needs_summary][:repair_score],
        addressed: t[:needs_summary][:addressed],
        groups_with_needs: t[:needs_summary][:groups_with_needs],
        class_ranking: t[:class_summary][:national]&.dig(:ranking)
      }
    end
  end

  def data_coverage_json(teams)
    {
      teams_without_portal_data: coached_college_seasons.select { |cs| cs.portal_statuses.empty? }.map { |cs| cs.college.name },
      teams_without_signees: teams.select { |t| t[:class_summary][:total_signed].zero? }.map { |t| t[:college][:name] },
      high_school_without_overall: teams.sum { |t| t[:position_scorecard].sum { |g| g[:signees].count { |s| s[:type] != "transfer" && s[:overall].nil? } } },
      transfers_without_overall: teams.sum { |t| t[:position_scorecard].sum { |g| g[:signees].count { |s| s[:type] == "transfer" && s[:overall].nil? } } },
      signees_in_no_position_group: teams.sum { |t| t[:class_summary][:total_signed] - t[:position_scorecard].sum { |g| g[:signees].size } }
    }
  end
end
