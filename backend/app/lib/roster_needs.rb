# Shared definition of "roster need" for the offseason podcasts. Portal
# Preview asks "what are we losing and where are we thin"; the National
# Signing Day Breakdown asks "did the recruiting class answer it". Both have
# to agree on what a position group is, how deep it should be, who counts as
# gone, and how much scholarship room a coach has, so those live here once.
module RosterNeeds
  # Minimum scholarship players a position group needs on hand to not be
  # thin, used to flag "needs depth." Deliberately a different grouping
  # than CollegeSeason::POSITION_GROUPS (WR and TE combined into one
  # skill-position bucket) — this is the offseason lens on the roster, not
  # the shared one. Linebackers lists both naming schemes (MLB/LOLB/ROLB and
  # MIKE/WILL/SAM) since a team only ever uses one, and either should count
  # toward the same depth target.
  DEPTH_GROUPS = {
    "Quarterbacks" => { positions: %w[QB], min_depth: 3 },
    "Backfield" => { positions: %w[HB FB], min_depth: 4 },
    "Wide Receivers/Tight Ends" => { positions: %w[WR TE], min_depth: 7 },
    "Offensive Line" => { positions: %w[LT LG C RG RT], min_depth: 12 },
    "Defensive Line" => { positions: %w[LE RE LEDG REDG DT], min_depth: 9 },
    "Linebackers" => { positions: %w[MLB LOLB ROLB MIKE WILL SAM], min_depth: 6 },
    "Secondary" => { positions: %w[CB FS SS], min_depth: 9 },
    "Kickers/Punters" => { positions: %w[K P], min_depth: 2 }
  }.freeze

  # Recruiting screens use broader labels than roster codes (OT, EDGE, ...).
  # Only needed to place a signee in a group; anything else is left unplaced.
  RECRUIT_POSITION_ALIASES = {
    "RB" => "HB", "OT" => "LT", "OG" => "LG", "OL" => "LT", "IOL" => "C",
    "DE" => "RE", "EDGE" => "RE", "DL" => "DT", "NT" => "DT",
    "OLB" => "LOLB", "ILB" => "MLB", "LB" => "MLB",
    "DB" => "CB", "S" => "FS", "NB" => "CB", "NICKEL" => "CB"
  }.freeze

  # How far below the conference-average starter at a specific position
  # counts as a real talent gap worth flagging, not just roster noise.
  STARTER_GAP_THRESHOLD = 5

  LEAVING_STATUSES = %w[transfer pro_draft graduation].freeze

  # NCAA-style initial-signee cap for one season (recruits + incoming
  # transfers together — both are tracked via SignedRecruit#transfer). The
  # 85-man roster cap is soft during the signing period (a team can go over
  # and trim before the season) rather than a hard stop on signing, so it's
  # reported as "room before a cut is needed," not a limit that blocks
  # scholarships_remaining.
  MAX_SCHOLARSHIPS = 35
  MAX_ROSTER_SIZE = 85

  module_function

  def leaving?(portal_status)
    LEAVING_STATUSES.include?(portal_status&.status)
  end

  # The depth group a position belongs to, or nil when it can't be placed.
  def group_for(position)
    code = PositionBoardMapping.canonical(position)
    code = RECRUIT_POSITION_ALIASES.fetch(code, code)
    DEPTH_GROUPS.find { |_group, config| (config[:positions].map { |p| PositionBoardMapping.canonical(p) }).include?(code) }&.first
  end

  def top_player_at(college_season, position)
    candidates = college_season.student_seasons.select { |ss| ss.position == position && ss.overall.present? }
    candidates.max_by(&:overall)
  end

  # scholarships_used counts every SignedRecruit this cycle regardless of
  # SignedRecruit#transfer — a traditional signee and an incoming portal
  # transfer both burn the same scholarship slot. roster_room_before_cuts_needed
  # is informational (the 85 cap is a trim-by-season-start deadline, not a
  # signing blocker), so it can go negative without meaning anything's
  # actually wrong yet.
  def roster_math(college_season, roster_size:, departures:)
    scholarships_used = college_season.signed_recruits.count
    projected_before_signees = roster_size - departures
    projected_with_signees = projected_before_signees + scholarships_used

    {
      max_scholarships: MAX_SCHOLARSHIPS,
      scholarships_used: scholarships_used,
      scholarships_remaining: [ MAX_SCHOLARSHIPS - scholarships_used, 0 ].max,
      max_roster_size: MAX_ROSTER_SIZE,
      current_roster_size: roster_size,
      projected_roster_before_signees: projected_before_signees,
      projected_roster_with_signees_so_far: projected_with_signees,
      roster_room_before_cuts_needed: MAX_ROSTER_SIZE - projected_with_signees
    }
  end
end
