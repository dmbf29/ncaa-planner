# "Portal Preview" episode: reviews our coached teams' roster status right
# before the transfer portal opens, using PortalStatus rows uploaded from
# each team's "players leaving" screen. A "transfer" or "pro_draft" status
# means that player has ALREADY entered the portal/declared — there's no
# "keep them from leaving" moment left to have. persuasion_chance is the
# odds of talking them into RETURNING to campus instead, which is why
# every player gets sorted into a risk tier: confirmed gone (graduating,
# or already out with no real shot at a return), a genuine uncertain
# return (already out, but a real shot at coming back), a likely return
# (already out, but the numbers say they're probably coming back), or
# presumed staying (never left at all). That tier drives the departure
# lists and one half of position needs (a group's remaining depth once
# every likely-gone player — confirmed departures AND uncertain returns —
# is subtracted out; a below-medium persuasion chance rarely actually
# converts in practice, so it's planned around as a loss, not a maybe).
# The other half of position needs has nothing to do with who's leaving:
# it compares our starter at each individual position against the
# conference-wide average starter at that same position, so a position
# that's simply weak — not attrition-affected at all — still gets flagged
# as somewhere to improve, not just somewhere to replace.
class PortalPreviewSerializer
  # Minimum scholarship players a position group needs on hand to not be
  # thin, used to flag "needs depth." Deliberately a different grouping
  # than CollegeSeason::POSITION_GROUPS (WR and TE combined into one
  # skill-position bucket) — this is Portal Preview's own lens on the
  # roster, not the shared one. Linebackers lists both naming schemes
  # (MLB/LOLB/ROLB and MIKE/WILL/SAM) since a team only ever uses one, and
  # either should count toward the same depth target.
  DEPTH_GROUPS = {
    "Quarterbacks" => { positions: %w[QB], min_depth: 3 },
    "Backfield" => { positions: %w[HB FB], min_depth: 4 },
    "Wide Receivers/Tight Ends" => { positions: %w[WR TE], min_depth: 7 },
    "Offensive Line" => { positions: %w[LT LG C RG RT], min_depth: 12 },
    "Defensive Line" => { positions: %w[LE RE DT], min_depth: 8 },
    "Linebackers" => { positions: %w[MLB LOLB ROLB MIKE WILL SAM], min_depth: 6 },
    "Secondary" => { positions: %w[CB FS SS], min_depth: 8 },
    "Kickers/Punters" => { positions: %w[K P], min_depth: 2 }
  }.freeze

  # How far below the conference-average starter at a specific position
  # counts as a real talent gap worth flagging, not just roster noise.
  STARTER_GAP_THRESHOLD = 5

  # Persuasion chance bands, for a player already in the portal/draft
  # (persuasion_chance is the odds of getting them back to campus, not the
  # odds of having kept them from leaving in the first place):
  # - not_applicable/none: no realistic path back — as good as gone.
  # - extremely_low through medium: a genuine uncertain return, worth
  #   tracking.
  # - high and up: the numbers say they're probably coming back — still
  #   worth a mention (they DID enter the portal), but not treated as a
  #   real loss anywhere in the roster math.
  CONFIRMED_PERSUASION = %w[not_applicable none].freeze
  UNCERTAIN_RETURN_PERSUASION = %w[extremely_low very_low low medium].freeze
  LIKELY_RETURN_PERSUASION = %w[high very_high extremely_high guaranteed].freeze

  # A senior (no eligibility left regardless of the draft) who's also
  # pro_draft isn't an early exit — he was leaving via graduation either
  # way, and getting drafted is just extra detail on that departure, not a
  # different kind of loss. An underclassman (anything else) declaring
  # pro_draft IS a real early exit — they had eligibility left the team
  # was counting on. See senior?.
  SENIOR_CLASS_YEARS = %w[SR SR(RS)].freeze

  # NCAA-style initial-signee cap for one season (recruits + incoming
  # transfers together — see roster_math_json, both are tracked via
  # SignedRecruit#transfer). The 85-man roster cap is soft during the
  # signing period (a team can go over and trim before the season) rather
  # than a hard stop on signing, so it's reported as "room before a cut is
  # needed," not a limit that blocks scholarships_remaining.
  MAX_SCHOLARSHIPS = 35
  MAX_ROSTER_SIZE = 85

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
                    "who's declaring for the draft early as an underclassman with no real shot of coming back, " \
                    "who's already in the portal with a genuine chance of returning to campus, which starters " \
                    "are simply below the conference average at their position (whether they're leaving or " \
                    "not), which position groups are thin on bodies, and how much scholarship/roster room each " \
                    "coach has to fix it all, right before the transfer portal opens. Each team's segment ends " \
                    "with both hosts giving their own verdict on how bad the damage looks, then the whole " \
                    "episode closes with the hosts ranking our teams from most damage taken to least."
    }
  end

  def coached_college_seasons
    @coached_college_seasons ||= @season.college_seasons
                                         .includes(:college, :coach, student_seasons: :student, portal_statuses: {})
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

  def risk_tier(portal_status)
    return "on_roster" unless portal_status
    return "confirmed" if portal_status.status == "graduation"

    if %w[transfer pro_draft].include?(portal_status.status)
      return "confirmed" if CONFIRMED_PERSUASION.include?(portal_status.persuasion_chance)
      return "uncertain_return" if UNCERTAIN_RETURN_PERSUASION.include?(portal_status.persuasion_chance)
      return "likely_return" if LIKELY_RETURN_PERSUASION.include?(portal_status.persuasion_chance)
    end

    "likely_staying"
  end

  # For every roster-planning purpose (depth counts, roster-size math, the
  # per-position starter flag) a confirmed departure and an uncertain
  # return are treated identically — a below-medium persuasion chance
  # rarely actually converts (in practice more like 1 in 15 than a coin
  # flip), so planning around "he might come back" is planning around a
  # long shot, not a real possibility. Only likely_return (high+) is
  # treated as staying.
  def likely_gone?(portal_status)
    %w[confirmed uncertain_return].include?(risk_tier(portal_status))
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
    tiers = enriched.map { |e| risk_tier(e[:portal_status]) }
    severity_score = (departures[:graduating_seniors] + departures[:declaring_early] + departures[:slim_chance_of_return])
                      .sum { |d| d[:overall] || 0 }

    {
      roster_size: enriched.size,
      graduating_seniors: departures[:graduating_seniors].size,
      declaring_early: departures[:declaring_early].size,
      slim_chance_of_return: departures[:slim_chance_of_return].size,
      likely_return: tiers.count("likely_return"),
      likely_staying: tiers.count { |t| %w[on_roster likely_staying].include?(t) },
      severity_score: severity_score
    }
  end

  # Four narrative buckets, in order from "settled, no real drama" to
  # "still a live storyline":
  # - graduating_seniors: a senior's career is over regardless of the
  #   draft — plain graduation and a senior's pro_draft entry are the same
  #   story, just with an extra draft-round detail on the latter.
  # - declaring_early: an underclassman pro_draft entry with no realistic
  #   persuasion path back — a real early exit, no drama left in it.
  # - slim_chance_of_return: everyone still genuinely uncertain — an
  #   uncertain_return entry (transfer or pro_draft) or the rare
  #   unpersuadable transfer (no dedicated "settled" bucket of its own,
  #   since transfer never implies a graduation/draft story the way
  #   pro_draft or graduation do).
  # - likely_return: unchanged — probably coming back.
  def departures_json(enriched, unmatched_statuses)
    matched = enriched.filter_map { |e| departure_entry(e[:student_season], e[:portal_status]) }
    unmatched = unmatched_statuses.filter_map { |ps| departure_entry(nil, ps) }
    all = (matched + unmatched).sort_by { |d| -(d[:overall] || 0) }

    graduating_seniors = all.select { |d| d[:risk_tier] == "confirmed" && (d[:status] == "graduation" || d[:senior]) }
    declaring_early = all.select { |d| d[:risk_tier] == "confirmed" && d[:status] == "pro_draft" && !d[:senior] }
    confirmed_transfers = all.select { |d| d[:risk_tier] == "confirmed" && d[:status] == "transfer" }
    slim_chance_of_return = (all.select { |d| d[:risk_tier] == "uncertain_return" } + confirmed_transfers)
                             .sort_by { |d| -(d[:overall] || 0) }
    likely_return = all.select { |d| d[:risk_tier] == "likely_return" }

    {
      graduating_seniors: graduating_seniors,
      declaring_early: declaring_early,
      slim_chance_of_return: slim_chance_of_return,
      likely_return: likely_return,
      most_important: (graduating_seniors + declaring_early + slim_chance_of_return).sort_by { |d| -(d[:overall] || 0) }.first(5)
    }
  end

  def departure_entry(student_season, portal_status)
    return nil unless portal_status

    tier = risk_tier(portal_status)
    return nil unless %w[confirmed uncertain_return likely_return].include?(tier)

    {
      name: student_season ? student_season.student.name : portal_status.display_name,
      position: student_season ? student_season.position : portal_status.position,
      class_year: student_season ? student_season.class_year : portal_status.class_year,
      overall: student_season ? student_season.overall : portal_status.overall,
      status: portal_status.status,
      detail: detail_line(portal_status),
      persuasion_chance: portal_status.persuasion_chance,
      risk_tier: tier,
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
      remaining_entries = group_entries.reject { |e| likely_gone?(e[:portal_status]) }

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
      tier = risk_tier(status)

      {
        position: position,
        starter: { name: starter.student.name, overall: starter.overall, risk_tier: tier },
        conference_avg_starter_overall: conf[:average],
        conference_sample_size: conf[:sample_size],
        gap_to_average: gap,
        below_average: gap.present? && gap >= STARTER_GAP_THRESHOLD,
        starter_leaving: likely_gone?(status)
      }
    end
  end

  def top_player_at(college_season, position)
    candidates = college_season.student_seasons.select { |ss| ss.position == position && ss.overall.present? }
    candidates.max_by(&:overall)
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

  # scholarships_used counts every SignedRecruit this cycle regardless of
  # SignedRecruit#transfer — a traditional signee and an incoming portal
  # transfer both burn the same scholarship slot. roster_room_before_cuts_needed
  # is informational (the 85 cap is a trim-by-season-start deadline, not a
  # signing blocker), so it can go negative without meaning anything's
  # actually wrong yet. Like the position-need depth math, this assumes
  # every likely-gone player (confirmed + uncertain return) actually
  # leaves — see likely_gone?.
  def roster_math_json(college_season, enriched)
    scholarships_used = college_season.signed_recruits.count
    current_roster_size = enriched.size
    likely_departures = enriched.count { |e| likely_gone?(e[:portal_status]) }
    projected_before_signees = current_roster_size - likely_departures
    projected_with_signees = projected_before_signees + scholarships_used

    {
      max_scholarships: MAX_SCHOLARSHIPS,
      scholarships_used: scholarships_used,
      scholarships_remaining: [ MAX_SCHOLARSHIPS - scholarships_used, 0 ].max,
      max_roster_size: MAX_ROSTER_SIZE,
      current_roster_size: current_roster_size,
      projected_roster_before_signees: projected_before_signees,
      projected_roster_with_signees_so_far: projected_with_signees,
      roster_room_before_cuts_needed: MAX_ROSTER_SIZE - projected_with_signees
    }
  end

  # Worst-hit-first, by total overall walking out the door (graduating
  # seniors + early draft declarations + slim-chance-of-return combined —
  # likely_return isn't counted, since those players are probably coming
  # back) — a data backstop for the closing segment, not a verdict the app
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
             slim_chance_of_return: t[:summary][:slim_chance_of_return]
           }
         end
  end
end
