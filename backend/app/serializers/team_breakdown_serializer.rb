# "Roster Breakdown" episode, recorded once the offseason's progression has
# been applied: for each of its POSITION_GROUPS it compares our
# coached teams' STARTING rooms to each other and to the conference, and
# against the same programs a year ago. It opens with a team-level "where each
# team stands" segment (see TeamBreakdownMarkdownPresenter).
#
# Rooms are judged on their starters (STARTER_SLOTS), not a whole-room average,
# which a pile of backups drags around. Player ratings exist only for
# colleges with a scraped roster (see data_coverage); NIL spend and
# All-American honors are league-wide. Season stats exist only for our own
# teams, so last season's production is reported for them alone.
#
# Dev traits are deliberately never read: in the game they're visible only
# for a coach's own players, so they can't be used to compare teams.
#
# Everything that compares to "last year" is keyed on Student, which is shared
# across seasons, and is simply nil when there is no prior season on record or
# a player can't be found in it.
class TeamBreakdownSerializer
  # The game tracks NIL spend as abstract "points" (it can't use real money
  # since it's rated for all ages). We convert to a dollar figure for the
  # broadcast output since that reads far more naturally in a podcast script.
  DOLLARS_PER_NIL_POINT = 10_000

  # Every position room except kickers/punters, which aren't worth an
  # episode segment, in broadcast order: reversed from the usual QB-first
  # listing so the show builds up to the quarterbacks.
  POSITION_GROUPS = CollegeSeason::POSITION_GROUPS.except("Kickers/Punters").to_a.reverse.to_h.freeze

  # Screen labels used by NilSpend::Extractor differ from
  # CollegeSeason::POSITION_GROUPS' keys, so this bridges the two.
  POSITION_GROUP_NIL_KEYS = {
    "Quarterbacks" => "QB",
    "Running Backs" => "RB",
    "Wide Receivers" => "WR",
    "Tight Ends" => "TE",
    "Offensive Line" => "OL",
    "Defensive Line" => "DL",
    "Linebackers" => "LB",
    "Secondary" => "DB"
  }.freeze

  # How many of a room's best players count as its starters.
  STARTER_SLOTS = {
    "Quarterbacks" => 1,
    "Running Backs" => 2,
    "Wide Receivers" => 3,
    "Tight Ends" => 1,
    "Offensive Line" => 5,
    "Defensive Line" => 4,
    "Linebackers" => 3,
    "Secondary" => 4
  }.freeze

  # Last season's production per room: what to sort players by and how to
  # phrase their line. Offensive linemen have no stats to show.
  STAT_SPECS = {
    "Quarterbacks" => {
      sort: :passing_yards,
      line: ->(t) { "#{n(t[:passing_yards])} passing yards, #{t[:passing_tds]} TD, #{t[:passing_interceptions]} INT" }
    },
    "Running Backs" => {
      sort: :rushing_yards,
      line: ->(t) { "#{n(t[:rushing_yards])} rushing yards on #{t[:rushing_carries]} carries, #{t[:rushing_tds]} TD" }
    },
    "Wide Receivers" => {
      sort: :receiving_yards,
      line: ->(t) { "#{t[:receiving_receptions]} catches for #{n(t[:receiving_yards])} yards, #{t[:receiving_tds]} TD" }
    },
    "Tight Ends" => {
      sort: :receiving_yards,
      line: ->(t) { "#{t[:receiving_receptions]} catches for #{n(t[:receiving_yards])} yards, #{t[:receiving_tds]} TD" }
    },
    "Defensive Line" => {
      sort: :defense_sacks,
      line: ->(t) { "#{t[:defense_sacks].round(1)} sacks, #{t[:defense_tfl]} TFL, #{t[:defense_tackles]} tackles" }
    },
    "Linebackers" => {
      sort: :defense_tackles,
      line: ->(t) { "#{t[:defense_tackles]} tackles, #{t[:defense_tfl]} TFL, #{t[:defense_sacks].round(1)} sacks" }
    },
    "Secondary" => {
      sort: :defense_tackles,
      line: ->(t) { "#{t[:defense_tackles]} tackles, #{t[:defense_interceptions]} INT" }
    }
  }.freeze
  STAT_COLUMNS = %i[
    passing_yards passing_tds passing_interceptions rushing_yards rushing_carries rushing_tds
    receiving_receptions receiving_yards receiving_tds defense_tackles defense_tfl defense_sacks
    defense_interceptions
  ].freeze

  def self.n(number)
    ActiveSupport::NumberHelper.number_to_delimited(number)
  end

  def initialize(season)
    @season = season
  end

  # Recorded at the end of April, right after spring practice and months
  # before the season's first game. The season's year is the year it is PLAYED
  # in (a season runs August through January), so the spring ahead of it falls
  # in that same calendar year.
  RECORDING_MONTH = 4
  RECORDING_DAY = 30

  def as_json
    {
      focus: focus_json,
      season: { id: @season.id, year: @season.year, dynasty: @season.dynasty.name },
      broadcast_date: Date.new(@season.year, RECORDING_MONTH, RECORDING_DAY).iso8601,
      last_season_year: @season.year - 1,
      data_coverage: data_coverage_json,
      teams: coached_college_seasons.map { |cs| team_json(cs) },
      positions: POSITION_GROUPS.keys.map { |group| position_json(group) }
    }
  end

  private

  def focus_json
    {
      instructions: "Roster Breakdown for our #{coached_college_seasons.size} coached teams for the " \
                    "#{@season.year} season, recorded at the end of April #{@season.year} right after spring " \
                    "practice, with the #{@season.year} season still ahead and no games played. It opens with where each team " \
                    "stands, then goes position group by position group comparing our teams' starting rooms to " \
                    "each other, to the #{conference_label} and to a year ago, and closes with the hosts' " \
                    "verdicts. Rooms are judged on their starters, not the whole depth chart. Player-rating " \
                    "claims are only reliable for colleges with a scraped roster — see data_coverage."
    }
  end

  def conference_label
    coached_conferences.presence&.to_sentence || "conference"
  end

  # ---- loading ---------------------------------------------------------------

  # preload (not includes) wherever a string ORDER BY colleges.name is used, so
  # Rails doesn't turn it into one huge JOIN across every roster.
  def coached_college_seasons
    @coached_college_seasons ||= @season.college_seasons
                                         .preload(:college, :coach, student_seasons: :student)
                                         .where.not(coach_id: nil)
                                         .joins(:college)
                                         .order("colleges.name")
                                         .to_a
  end

  def coached_conferences
    @coached_conferences ||= coached_college_seasons.filter_map(&:conference).uniq
  end

  def conference_college_seasons
    @conference_college_seasons ||= @season.college_seasons
                                            .preload(:college, student_seasons: :student)
                                            .where(conference: coached_conferences)
                                            .to_a
  end

  def rostered_colleges
    @rostered_colleges ||= conference_college_seasons.select { |cs| cs.student_seasons.any? { |ss| ss.overall.present? } }
                                                       .map(&:college)
  end

  def all_americans
    @all_americans ||= AllAmerican.where(student_season: StudentSeason.where(college_season: conference_college_seasons))
                                   .preload(student_season: [ :student, { college_season: :college } ])
                                   .to_a
  end

  # ---- last year -----------------------------------------------------------

  def previous_season
    return @previous_season if defined?(@previous_season)

    @previous_season = @season.dynasty.seasons.find_by(year: @season.year - 1)
  end

  def previous_college_season(college_id)
    @previous_college_seasons ||= previous_season ? previous_season.college_seasons.preload(student_seasons: :student).index_by(&:college_id) : {}
    @previous_college_seasons[college_id]
  end

  # student_id => that student's StudentSeason last year (whichever college
  # they were at), for everyone on a conference roster this year.
  def previous_by_student
    @previous_by_student ||= if previous_season
      StudentSeason.where(college_season_id: previous_season.college_seasons.select(:id),
                          student_id: StudentSeason.where(college_season: conference_college_seasons).select(:student_id))
                   .preload(college_season: :college).index_by(&:student_id)
    else
      {}
    end
  end

  # Where a player came from, or nil when we can't tell (no prior season on
  # record, or a non-freshman who isn't in it). Transfers carry the school
  # they left so the hosts can say "transferred from X".
  def origin_json(student_season)
    return nil unless previous_season

    previous = previous_by_student[student_season.student_id]
    if previous
      same_college = previous.college_season.college_id == student_season.college_season.college_id
      same_college ? { type: "returning" } : { type: "transfer", from_college: previous.college_season.college.name }
    elsif student_season.class_year == "FR"
      { type: "true_freshman" }
    end
  end

  def player_json(student_season)
    return nil unless student_season

    previous = previous_by_student[student_season.student_id]
    {
      name: student_season.student.name,
      position: student_season.position,
      overall: student_season.overall,
      class_year: student_season.class_year,
      origin: origin_json(student_season),
      previous_overall: previous&.overall,
      overall_change: previous&.overall && student_season.overall && (student_season.overall - previous.overall)
    }
  end

  # ---- rooms -------------------------------------------------------------------

  # A college's players in one room, best first, and the starters among them.
  def room(college_season, group)
    @rooms ||= {}
    @rooms[[ college_season.id, group ]] ||= begin
      positions = POSITION_GROUPS.fetch(group)
      players = college_season.student_seasons.select { |ss| positions.include?(ss.position) && ss.overall.present? }
                              .sort_by { |ss| -ss.overall }
      { players: players, starters: starters_of(group, players) }
    end
  end

  def starters_of(group, players)
    players.first(STARTER_SLOTS.fetch(group))
  end

  def average(values)
    values.empty? ? nil : (values.sum.to_f / values.size).round(1)
  end

  def starter_average(college_season, group)
    average(room(college_season, group)[:starters].map(&:overall))
  end

  # [{college, average, coached_by_us}] best first, for every conference
  # college with starters in this room.
  def room_leaderboard(group)
    @room_leaderboards ||= {}
    @room_leaderboards[group] ||= conference_college_seasons.filter_map do |cs|
      avg = starter_average(cs, group)
      avg && { college: { id: cs.college.id, name: cs.college.name }, average: avg, coached_by_us: cs.coach_id.present? }
    end.sort_by { |entry| [ -entry[:average], entry[:college][:name] ] }
  end

  # Ties share a rank (competition ranking), so two 76.3 rooms are both 2nd.
  def room_rank(college_season, group)
    leaderboard = room_leaderboard(group)
    mine = leaderboard.find { |entry| entry[:college][:id] == college_season.college_id }
    mine && { rank: 1 + leaderboard.count { |entry| entry[:average] > mine[:average] }, of: leaderboard.size }
  end

  def last_year_room(college_season, group)
    previous = previous_college_season(college_season.college_id)
    return nil unless previous

    positions = POSITION_GROUPS.fetch(group)
    players = previous.student_seasons.select { |ss| positions.include?(ss.position) && ss.overall.present? }.sort_by { |ss| -ss.overall }
    last_average = average(starters_of(group, players).map(&:overall))
    this_average = starter_average(college_season, group)
    {
      starter_average: last_average,
      change: last_average && this_average && (this_average - last_average).round(1)
    }
  end

  # The starter in the room who gained / lost the most since last year. Only
  # starters, so the storyline is about the lineup rather than a backup.
  def movers(college_season, group)
    changed = room(college_season, group)[:starters].filter_map do |ss|
      player = player_json(ss)
      player if player[:overall_change]
    end
    {
      riser: changed.max_by { |p| p[:overall_change] }&.then { |p| p[:overall_change].positive? ? p : nil },
      faller: changed.min_by { |p| p[:overall_change] }&.then { |p| p[:overall_change].negative? ? p : nil }
    }
  end

  # ---- team level ----------------------------------------------------------

  def team_json(college_season)
    previous = previous_college_season(college_season.college_id)
    starters = POSITION_GROUPS.keys.flat_map { |group| room(college_season, group)[:starters] }
    origins = starters.filter_map { |ss| origin_json(ss)&.dig(:type) }

    {
      college: { id: college_season.college.id, name: college_season.college.name, conference: college_season.conference },
      coach: { id: college_season.coach.id, name: college_season.coach.name },
      ratings: {
        overall: college_season.overall,
        offense: college_season.offense,
        defense: college_season.defense,
        prestige: college_season.prestige,
        conference_rank: overall_rank(college_season),
        change_from_last_year: previous&.overall && college_season.overall && (college_season.overall - previous.overall)
      },
      last_season: previous && {
        wins: previous.wins, losses: previous.losses,
        conference_wins: previous.conference_wins, conference_losses: previous.conference_losses
      },
      starting_lineup: {
        transfers: origins.count("transfer"),
        true_freshmen: origins.count("true_freshman"),
        returning: origins.count("returning"),
        total: starters.size
      }
    }
  end

  def overall_rank(college_season)
    return nil unless college_season.overall

    rated = conference_college_seasons.select(&:overall)
    { rank: 1 + rated.count { |cs| cs.overall > college_season.overall }, of: rated.size }
  end

  # ---- positions -----------------------------------------------------------

  def position_json(group)
    nil_key = POSITION_GROUP_NIL_KEYS.fetch(group)
    our_teams = coached_college_seasons.map { |cs| team_position_json(cs, group, nil_key) }

    {
      position_group: group,
      our_teams: our_teams,
      strongest_of_ours: pick(our_teams) { |t| [ t.dig(:conference_rank, :rank) || 999, -(t[:starter_average] || 0) ] },
      weakest_of_ours: pick(our_teams) { |t| [ -(t.dig(:conference_rank, :rank) || 0), t[:starter_average] || 999 ] },
      most_improved: pick(our_teams, :change) { |t| -(t.dig(:last_year, :change) || -999) },
      conference: conference_position_json(group, nil_key)
    }
  end

  # The team a ranking block picks out, as {college, value-ish context}; nil
  # when there's nothing to rank on.
  def pick(our_teams, kind = nil, &sort_key)
    candidates = our_teams.select { |t| kind == :change ? t.dig(:last_year, :change) : t[:starter_average] }
    best = candidates.min_by(&sort_key)
    best && { college: best[:college], starter_average: best[:starter_average], conference_rank: best[:conference_rank], change: best.dig(:last_year, :change) }
  end

  def team_position_json(college_season, group, nil_key)
    this_room = room(college_season, group)
    {
      college: { id: college_season.college.id, name: college_season.college.name },
      coach: { id: college_season.coach.id, name: college_season.coach.name },
      starters: this_room[:starters].map { |ss| player_json(ss) },
      starter_average: starter_average(college_season, group),
      player_count: this_room[:players].size,
      conference_rank: room_rank(college_season, group),
      last_year: last_year_room(college_season, group),
      team_biggest_room_change: room_change_flag(college_season, group),
      movers: movers(college_season, group),
      nil_spend: nil_json(college_season, nil_key),
      all_americans: all_americans_for_college(college_season.college_id, group).map { |aa| all_american_json(aa) },
      last_season_production: production_json(college_season, group)
    }
  end

  def conference_position_json(group, nil_key)
    best = conference_college_seasons.flat_map { |cs| cs.student_seasons.select { |ss| POSITION_GROUPS.fetch(group).include?(ss.position) && ss.overall } }.max_by(&:overall)
    {
      top_rooms: room_leaderboard(group).first(3),
      best_player: best && player_json(best).merge(college: { id: best.college_season.college.id, name: best.college_season.college.name }, coached_by_us: best.college_season.coach_id.present?),
      all_americans: all_americans_for_group(group).map { |aa| all_american_json(aa) },
      nil_leaders: nil_leaderboard(nil_key).first(3)
    }
  end

  # ---- NIL -----------------------------------------------------------------

  def nil_dollars(college_season, nil_key)
    points = college_season.nil_spend_by_position[nil_key]
    return nil if points.blank?

    points * DOLLARS_PER_NIL_POINT
  end

  def nil_leaderboard(nil_key)
    @nil_leaderboards ||= {}
    @nil_leaderboards[nil_key] ||= conference_college_seasons.filter_map do |cs|
      amount = nil_dollars(cs, nil_key)
      amount && { college: { id: cs.college.id, name: cs.college.name }, amount: amount, coached_by_us: cs.coach_id.present? }
    end.sort_by { |entry| [ -entry[:amount], entry[:college][:name] ] }
  end

  def nil_json(college_season, nil_key)
    amount = nil_dollars(college_season, nil_key)
    return nil unless amount

    leaderboard = nil_leaderboard(nil_key)
    {
      dollars: amount,
      rank: 1 + leaderboard.count { |entry| entry[:amount] > amount },
      of: leaderboard.size,
      conference_average: (leaderboard.sum { |entry| entry[:amount] }.to_f / leaderboard.size).round
    }
  end

  # ---- All-Americans -----------------------------------------------------

  def all_americans_for_group(group)
    positions = POSITION_GROUPS.fetch(group)
    all_americans.select { |aa| positions.include?(aa.student_season.position) }
  end

  def all_americans_for_college(college_id, group)
    all_americans_for_group(group).select { |aa| aa.student_season.college_season.college_id == college_id }
  end

  def all_american_json(all_american)
    student_season = all_american.student_season
    {
      name: student_season.student.name,
      college: { id: student_season.college_season.college.id, name: student_season.college_season.college.name },
      position: student_season.position,
      national: all_american.national,
      conference: all_american.conference,
      tier: all_american.tier,
      preseason: all_american.preseason,
      origin: origin_json(student_season)
    }
  end

  # ---- last season's production (our teams only) -------------------------

  # The room's top producer from last year who is still on this team, and the
  # top producer who is gone, so the hosts can talk about what returns and what
  # walked out the door. Only our teams have season stats.
  def production_json(college_season, group)
    spec = STAT_SPECS[group]
    previous = previous_college_season(college_season.college_id)
    return nil unless spec && previous

    positions = POSITION_GROUPS.fetch(group)
    current_students = college_season.student_seasons.index_by(&:student_id)
    producers = previous.student_seasons.select { |ss| positions.include?(ss.position) }.filter_map do |ss|
      totals = stat_totals[ss.id]
      totals && totals[spec[:sort]].to_f.positive? ? { student_season: ss, totals: totals } : nil
    end
    return nil if producers.empty?

    returning, gone = producers.partition { |entry| current_students.key?(entry[:student_season].student_id) }
    {
      returning_leader: production_entry(returning, spec) { |ss| current_students[ss.student_id] },
      lost_leader: production_entry(gone, spec)
    }
  end

  def production_entry(entries, spec)
    top = entries.max_by { |entry| entry[:totals][spec[:sort]] }
    return nil unless top

    last_year = top[:student_season]
    now = block_given? ? yield(last_year) : nil
    {
      name: last_year.student.name,
      position: last_year.position,
      class_year_last_year: last_year.class_year,
      stat_line: spec[:line].call(top[:totals]),
      current_overall: now&.overall,
      current_class_year: now&.class_year
    }
  end

  # student_season_id => summed season totals, for last year's coached rosters.
  def stat_totals
    @stat_totals ||= begin
      ids = coached_college_seasons.filter_map { |cs| previous_college_season(cs.college_id) }.flat_map { |cs| cs.student_seasons.map(&:id) }
      StudentGameStat.where(student_season_id: ids).group_by(&:student_season_id).transform_values do |rows|
        STAT_COLUMNS.to_h { |column| [ column, rows.sum { |row| row[column].to_f } ] }
                    .transform_values { |value| (value % 1).zero? ? value.to_i : value }
      end
    end
  end

  # ---- biggest room changes ---------------------------------------------------

  # The one room where a team improved the most from last year and the one
  # where it fell the most, so each room's block can say "this is the team's
  # biggest jump / drop". A team with no year-over-year data, or with no
  # room that actually rose / fell, gets nil for that side.
  def room_changes(college_season)
    @room_changes ||= {}
    @room_changes[college_season.id] ||= begin
      changes = POSITION_GROUPS.keys.filter_map do |group|
        change = last_year_room(college_season, group)&.dig(:change)
        change && [ group, change ]
      end
      jump = changes.max_by { |_group, change| change }
      drop = changes.min_by { |_group, change| change }
      { jump: jump && jump.last.positive? ? jump.first : nil, drop: drop && drop.last.negative? ? drop.first : nil }
    end
  end

  # :jump, :drop or nil for this team's room.
  def room_change_flag(college_season, group)
    changes = room_changes(college_season)
    return :jump if changes[:jump] == group
    return :drop if changes[:drop] == group

    nil
  end

  def data_coverage_json
    {
      rostered_colleges: rostered_colleges.map(&:name),
      colleges_with_nil_spend_data: conference_college_seasons.count { |cs| cs.nil_spend_by_position.present? },
      last_season_available: previous_season.present?,
      note: "Player ratings and 'best/strongest' claims are only reliable for the colleges listed in " \
            "rostered_colleges — our own coached teams plus whichever conference peers happen to have a scraped " \
            "roster. Season stats exist for our own teams only."
    }
  end
end
