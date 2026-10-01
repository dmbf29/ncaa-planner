# "Portal Preview" episode: reviews our coached teams' roster status right
# before the transfer portal opens, using PortalStatus rows uploaded from
# each team's "players leaving" screen. Any "transfer", "pro_draft", or
# "graduation" status is treated as a player who is leaving; "staying"
# means the player considered leaving but decided to stay, and is listed
# separately as a close call without counting as a loss. Leaving players
# drive the departure lists and one half of position needs (a group's
# remaining depth once every leaving player is subtracted out).
# The other half of position needs has nothing to do with who's leaving:
# it compares our starter at each individual position against the
# conference-wide average starter at that same position, so a position
# that's simply weak — not attrition-affected at all — still gets flagged
# as somewhere to improve, not just somewhere to replace.
class PortalPreviewSerializer
  DEPTH_GROUPS = RosterNeeds::DEPTH_GROUPS
  STARTER_GAP_THRESHOLD = RosterNeeds::STARTER_GAP_THRESHOLD
  LEAVING_STATUSES = RosterNeeds::LEAVING_STATUSES

  # A senior (no eligibility left regardless of the draft) who's also
  # pro_draft isn't an early exit — he was leaving via graduation either
  # way, and getting drafted is just extra detail on that departure, not a
  # different kind of loss. An underclassman (anything else) declaring
  # pro_draft IS a real early exit — they had eligibility left the team
  # was counting on. See senior?.
  SENIOR_CLASS_YEARS = %w[SR SR(RS)].freeze

  MAX_SCHOLARSHIPS = RosterNeeds::MAX_SCHOLARSHIPS
  MAX_ROSTER_SIZE = RosterNeeds::MAX_ROSTER_SIZE

  def initialize(season)
    @season = season
  end

  def as_json
    teams = coached_college_seasons.map { |cs| team_json(cs) }

    {
      focus: focus_json,
      season: { id: @season.id, year: @season.year, dynasty: @season.dynasty.name },
      teams: teams,
      severity_ranking: severity_ranking_json(teams)
    }
  end

  private

  def focus_json
    {
      instructions: "Portal Preview for our #{coached_college_seasons.size} coached teams — a roster-planning " \
                    "look at who's graduating (seniors, whether or not they're also declaring for the draft), " \
                    "who's declaring for the draft early as an underclassman, who's transferring out and why, " \
                    "which starters " \
                    "are simply below the conference average at their position (whether they're leaving or " \
                    "not), which position groups are thin on bodies, and how much scholarship/roster room each " \
                    "coach has to fix it all, right before the transfer portal opens. Each team's segment ends " \
                    "with both hosts giving their own verdict on how bad the damage looks, then the whole " \
                    "episode closes with the hosts ranking our teams from most damage taken to least."
    }
  end

  def coached_college_seasons
    @coached_college_seasons ||= @season.college_seasons
                                         .includes(:college, :coach, student_seasons: %i[student student_game_stats], portal_statuses: {})
                                         .where.not(coach_id: nil)
                                         .joins(:college)
                                         .order("colleges.name")
                                         .to_a
  end

  def team_json(college_season)
    statuses_by_student_season_id = college_season.portal_statuses.index_by(&:student_season_id)
    unmatched_statuses = college_season.portal_statuses.select { |ps| ps.student_season_id.nil? }
    enriched = college_season.student_seasons.map { |ss| { student_season: ss, portal_status: statuses_by_student_season_id[ss.id] } }
    departures = departures_json(enriched, unmatched_statuses)

    {
      college: college_json(college_season.college, college_season.conference),
      coach: { id: college_season.coach.id, name: college_season.coach.name },
      summary: summary_json(enriched, departures),
      departures: departures,
      position_needs: position_needs_json(college_season, enriched, statuses_by_student_season_id),
      roster_math: roster_math_json(college_season, enriched)
    }
  end

  def college_json(college, conference)
    { id: college.id, name: college.name, conference: conference }
  end

  def all_college_seasons
    @all_college_seasons ||= @season.college_seasons.includes(:college, student_seasons: :student).to_a
  end

  def college_seasons_by_conference
    @college_seasons_by_conference ||= all_college_seasons.group_by(&:conference)
  end

  def leaving?(portal_status)
    RosterNeeds.leaving?(portal_status)
  end

  # Prefers the matched student_season's class_year (authoritative) over
  # the raw screenshot value on portal_status, same precedence used
  # elsewhere for a matched row. Status-agnostic — used both to fold a
  # senior's pro_draft entry in with plain graduations, and to keep an
  # underclassman's pro_draft entry out of that bucket.
  def senior?(student_season, portal_status)
    class_year = student_season&.class_year || portal_status&.class_year
    SENIOR_CLASS_YEARS.include?(class_year)
  end

  def summary_json(enriched, departures)
    severity_score = (departures[:graduating_seniors] + departures[:declaring_early] + departures[:transferring])
                      .sum { |d| d[:overall] || 0 }

    {
      roster_size: enriched.size,
      graduating_seniors: departures[:graduating_seniors].size,
      declaring_early: departures[:declaring_early].size,
      transferring: departures[:transferring].size,
      decided_to_stay: departures[:decided_to_stay].size,
      staying: enriched.count { |e| !leaving?(e[:portal_status]) },
      severity_score: severity_score
    }
  end

  # Three departure buckets:
  # - graduating_seniors: a senior's career is over regardless of the
  #   draft — plain graduation and a senior's pro_draft entry are the same
  #   story, just with an extra draft-round detail on the latter.
  # - declaring_early: an underclassman pro_draft entry — a real early
  #   exit with eligibility left on the table.
  # - transferring: in the portal, with the reason they gave.
  # decided_to_stay isn't a departure at all — players who considered
  # leaving but stayed — but it's built from the same rows, so it travels
  # here as a close-calls list and is excluded from most_important.
  def departures_json(enriched, unmatched_statuses)
    matched = enriched.filter_map { |e| departure_entry(e[:student_season], e[:portal_status]) }
    unmatched = unmatched_statuses.filter_map { |ps| departure_entry(nil, ps) }
    listed = (matched + unmatched).sort_by { |d| -(d[:overall] || 0) }
    decided_to_stay = listed.select { |d| d[:status] == "staying" }
    all = listed - decided_to_stay

    graduating_seniors = all.select { |d| d[:status] == "graduation" || (d[:status] == "pro_draft" && d[:senior]) }
    declaring_early = all.select { |d| d[:status] == "pro_draft" && !d[:senior] }
    transferring = all.select { |d| d[:status] == "transfer" }

    {
      graduating_seniors: graduating_seniors,
      declaring_early: declaring_early,
      transferring: transferring,
      decided_to_stay: decided_to_stay,
      most_important: all.first(5)
    }
  end

  # overall prefers the screenshot's value: the portal screen is read at
  # the end of the season, while the roster's overall is usually from the
  # start of it, so the screenshot reflects in-season progression. Starter
  # comparisons (starter_entries) stay on roster overalls, since the other
  # teams in the conference only have roster data to compare against.
  def departure_entry(student_season, portal_status)
    return nil unless leaving?(portal_status) || portal_status&.status == "staying"

    {
      name: student_season ? student_season.student.name : portal_status.display_name,
      position: student_season ? student_season.position : portal_status.position,
      class_year: student_season ? student_season.class_year : portal_status.class_year,
      overall: portal_status.overall || student_season&.overall,
      games_played: student_season&.student_game_stats&.size,
      status: portal_status.status,
      detail: detail_line(portal_status),
      senior: senior?(student_season, portal_status),
      matched: student_season.present?
    }
  end

  def detail_line(portal_status)
    case portal_status.status
    when "transfer" then portal_status.transfer_reason
    when "pro_draft" then draft_pick_detail(portal_status.projected_draft_round)
    end
  end

  def draft_pick_detail(round)
    return nil unless round

    "Projected #{ordinal(round)} Round NFL Draft Pick"
  end

  def ordinal(number)
    return "#{number}th" if (11..13).cover?(number % 100)

    case number % 10
    when 1 then "#{number}st"
    when 2 then "#{number}nd"
    when 3 then "#{number}rd"
    else "#{number}th"
    end
  end

  def position_needs_json(college_season, enriched, statuses_by_student_season_id)
    DEPTH_GROUPS.map do |group, config|
      positions = config[:positions]
      group_entries = enriched.select { |e| positions.include?(e[:student_season].position) }
      remaining_entries = group_entries.reject { |e| leaving?(e[:portal_status]) }

      {
        position_group: group,
        current_depth: group_entries.size,
        min_healthy_depth: config[:min_depth],
        remaining_depth: remaining_entries.size,
        needs_depth: remaining_entries.size < config[:min_depth],
        starters: starter_entries(college_season, positions, statuses_by_student_season_id)
      }
    end
  end

  # One entry per distinct position code this team actually has a player
  # at (so a team running MIKE/WILL/SAM never gets MLB/LOLB/ROLB entries,
  # and vice versa). Compares our starter — the single highest-overall
  # player at that exact position, not a group blend — against the
  # conference-wide average starter at that same position, regardless of
  # whether our guy is leaving. This answers "are we actually good here,"
  # separate from the group-level depth numbers answering "do we have
  # enough bodies."
  def starter_entries(college_season, positions, statuses_by_student_season_id)
    positions.filter_map do |position|
      starter = top_player_at(college_season, position)
      next nil unless starter

      conf = conference_starter_average(college_season.conference, position)
      gap = conf[:average] && (conf[:average] - starter.overall).round(1)
      status = statuses_by_student_season_id[starter.id]

      {
        position: position,
        starter: { name: starter.student.name, overall: starter.overall },
        conference_avg_starter_overall: conf[:average],
        conference_sample_size: conf[:sample_size],
        gap_to_average: gap,
        below_average: gap.present? && gap >= STARTER_GAP_THRESHOLD,
        starter_leaving: leaving?(status)
      }
    end
  end

  def top_player_at(college_season, position)
    RosterNeeds.top_player_at(college_season, position)
  end

  # Averaged across every college in the same conference with a scraped
  # roster at this exact position — a college with no roster data simply
  # doesn't contribute (same reasoning as TeamBreakdownSerializer's
  # data_coverage caveat: rating claims are only reliable where there's a
  # roster). conference_sample_size travels with the average so a number
  # built from just one or two peers can be treated with the right amount
  # of skepticism.
  def conference_starter_average(conference, position)
    @conference_starter_averages ||= {}
    @conference_starter_averages[[ conference, position ]] ||= begin
      peers = college_seasons_by_conference.fetch(conference, [])
      starter_overalls = peers.filter_map { |cs| top_player_at(cs, position)&.overall }
      {
        average: starter_overalls.present? ? (starter_overalls.sum.to_f / starter_overalls.size).round(1) : nil,
        sample_size: starter_overalls.size
      }
    end
  end

  def roster_math_json(college_season, enriched)
    RosterNeeds.roster_math(
      college_season,
      roster_size: enriched.size,
      departures: enriched.count { |e| leaving?(e[:portal_status]) }
    )
  end

  # Worst-hit-first, by total overall walking out the door (graduating
  # seniors + early draft declarations + transfers combined) — a data backstop for the closing segment, not a verdict the app
  # is rendering; the hosts do that. Per-category counts travel along so
  # the segment can say how many of each kind of departure hit each team,
  # not just a single blended score.
  def severity_ranking_json(teams)
    teams.sort_by { |t| -t[:summary][:severity_score] }
         .map do |t|
           {
             college: t[:college],
             severity_score: t[:summary][:severity_score],
             graduating_seniors: t[:summary][:graduating_seniors],
             declaring_early: t[:summary][:declaring_early],
             transferring: t[:summary][:transferring]
           }
         end
  end
end
