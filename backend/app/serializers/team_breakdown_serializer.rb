# Preseason "position group by position group" episode: for each of
# CollegeSeason::POSITION_GROUPS, compares our coached teams to each other
# (best player, average rating, NIL spend, All-Americans) and situates them
# against the rest of the conference using the two signals that are
# actually available league-wide regardless of roster data — NIL spend by
# position and All-American honors — rather than player ratings, which we
# only have for colleges with a scraped roster. See data_coverage in the
# output for exactly which colleges that is.
class TeamBreakdownSerializer
  # The game tracks NIL spend as abstract "points" (it can't use real money
  # since it's rated for all ages). We convert to a dollar figure for the
  # broadcast output since that reads far more naturally in a podcast script.
  DOLLARS_PER_NIL_POINT = 10_000

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
    "Secondary" => "DB",
    "Kickers/Punters" => "K/P"
  }.freeze

  def initialize(season)
    @season = season
  end

  def as_json
    {
      focus: focus_json,
      season: { id: @season.id, year: @season.year, dynasty: @season.dynasty.name },
      data_coverage: data_coverage_json,
      positions: CollegeSeason::POSITION_GROUPS.keys.map { |group| position_json(group) }
    }
  end

  private

  def focus_json
    {
      instructions: "This is a preseason position-group-by-position-group breakdown of our " \
                    "#{coached_college_seasons.size} coached teams for the #{@season.year} season — no games have " \
                    "been played yet. For each position: compare our teams to each other (strongest, who should be " \
                    "worried, NIL investment), and use the conference section for wider #{conference_label} " \
                    "context. Player-rating claims (best player, strongest team) are only reliable for colleges " \
                    "with a scraped roster — see data_coverage. NIL spend and All-American honors are tracked " \
                    "league-wide, so lean on those for claims about teams we don't have full rosters for."
    }
  end

  def conference_label
    coached_conferences.presence&.to_sentence || "conference"
  end

  def coached_college_seasons
    @coached_college_seasons ||= @season.college_seasons
                                         .includes(:college, :coach, :student_seasons)
                                         .where.not(coach_id: nil)
                                         .joins(:college)
                                         .order("colleges.name")
                                         .to_a
  end

  def coached_conferences
    @coached_conferences ||= coached_college_seasons.filter_map { |cs| cs.college.conference }.uniq
  end

  def conference_college_seasons
    @conference_college_seasons ||= @season.college_seasons
                                            .includes(:college, :coach, :student_seasons)
                                            .joins(:college)
                                            .where(colleges: { conference: coached_conferences })
                                            .to_a
  end

  def rostered_colleges
    @rostered_colleges ||= conference_college_seasons.select { |cs| cs.student_seasons.any? { |ss| ss.overall.present? } }
                                                       .map(&:college)
  end

  def all_americans
    @all_americans ||= AllAmerican.where(student_season: StudentSeason.where(college_season: conference_college_seasons))
                                   .includes(student_season: [ :student, { college_season: :college } ])
                                   .to_a
  end

  # {student_season, owning college_season} pairs, kept together (rather
  # than flat-mapped to bare StudentSeasons) so the conference-wide "best
  # rated player" lookup can report which college they're on without an
  # extra query per player.
  def conference_student_seasons_by_group
    @conference_student_seasons_by_group ||= begin
      pairs = conference_college_seasons.flat_map { |cs| cs.student_seasons.map { |ss| [ ss, cs ] } }
      CollegeSeason::POSITION_GROUPS.transform_values do |positions|
        pairs.select { |ss, _cs| positions.include?(ss.position) && ss.overall.present? }
             .sort_by { |ss, _cs| -ss.overall }
      end
    end
  end

  # Computed in Ruby from the already-preloaded student_seasons association
  # rather than via CollegeSeason#position_group_averages (which issues a
  # fresh `.average(:overall)` query per group) — this runs across every
  # conference college_season, not just our 4 coached ones, so avoiding
  # 14 colleges x 9 groups of N+1 queries matters here.
  def players_by_college_season_and_group(college_season)
    @players_by_college_season_and_group ||= {}
    @players_by_college_season_and_group[college_season.id] ||= CollegeSeason::POSITION_GROUPS.transform_values do |positions|
      college_season.student_seasons.select { |ss| positions.include?(ss.position) }.sort_by { |ss| -(ss.overall || -1) }
    end
  end

  def average_rating(college_season, group)
    rated = players_by_college_season_and_group(college_season)[group].select { |ss| ss.overall.present? }
    return nil if rated.empty?

    (rated.sum(&:overall).to_f / rated.size).round
  end

  def average_rating_leaderboard(group)
    @average_rating_leaderboard ||= {}
    @average_rating_leaderboard[group] ||= conference_college_seasons.filter_map do |cs|
      avg = average_rating(cs, group)
      next unless avg

      { college: { id: cs.college.id, name: cs.college.name }, average: avg, coached_by_us: cs.coach_id.present? }
    end.sort_by { |entry| -entry[:average] }
  end

  def conference_rank(college_season, group)
    leaderboard = average_rating_leaderboard(group)
    index = leaderboard.find_index { |entry| entry[:college][:id] == college_season.college_id }
    index && { rank: index + 1, of: leaderboard.size }
  end

  def data_coverage_json
    {
      rostered_colleges: rostered_colleges.map(&:name),
      colleges_with_nil_spend_data: conference_college_seasons.count { |cs| cs.nil_spend_by_position.present? },
      note: "Player ratings and 'best/strongest' claims are only reliable for the colleges listed in " \
            "rostered_colleges — our own coached teams plus whichever conference peers happen to have a scraped " \
            "roster. Everyone else may have real talent we simply have no rating data for."
    }
  end

  def position_json(group)
    positions = CollegeSeason::POSITION_GROUPS.fetch(group)
    nil_key = POSITION_GROUP_NIL_KEYS.fetch(group)
    our_teams = coached_college_seasons.map { |cs| team_position_json(cs, group, nil_key) }

    {
      position_group: group,
      our_teams: our_teams,
      strongest_of_ours: extreme(our_teams, :average_rating),
      team_to_worry_about: extreme(our_teams, :average_rating, lowest: true),
      most_nil_invested_of_ours: extreme(our_teams, :nil_spend),
      should_spend_more: extreme(our_teams, :nil_spend, lowest: true),
      conference: conference_position_json(group, nil_key)
    }
  end

  def team_position_json(college_season, group, nil_key)
    players = players_by_college_season_and_group(college_season)[group]

    {
      college: { id: college_season.college.id, name: college_season.college.name },
      coach: { id: college_season.coach.id, name: college_season.coach.name },
      best_player: player_json(players.first),
      average_rating: average_rating(college_season, group),
      conference_rank: conference_rank(college_season, group),
      player_count: players.size,
      nil_spend: nil_spend_dollars(college_season, nil_key),
      all_americans: all_americans_for_college(college_season.college_id, group).map { |aa| all_american_json(aa) }
    }
  end

  def nil_spend_dollars(college_season, nil_key)
    points = college_season.nil_spend_by_position[nil_key]
    return nil if points.blank?

    points * DOLLARS_PER_NIL_POINT
  end

  def conference_position_json(group, nil_key)
    top_pair = conference_student_seasons_by_group[group].first
    {
      average_rating_leaderboard: average_rating_leaderboard(group),
      all_americans: all_americans_for_group(group).map { |aa| all_american_json(aa) },
      nil_spend_leaderboard: nil_spend_leaderboard(nil_key),
      best_rated_player: top_pair && conference_player_json(*top_pair)
    }
  end

  def all_americans_for_group(group)
    positions = CollegeSeason::POSITION_GROUPS.fetch(group)
    all_americans.select { |aa| positions.include?(aa.student_season.position) }
  end

  def all_americans_for_college(college_id, group)
    all_americans_for_group(group).select { |aa| aa.student_season.college_season.college_id == college_id }
  end

  def nil_spend_leaderboard(nil_key)
    conference_college_seasons.filter_map do |cs|
      amount = nil_spend_dollars(cs, nil_key)
      next if amount.blank?

      { college: { id: cs.college.id, name: cs.college.name }, amount: amount, coached_by_us: cs.coach_id.present? }
    end.sort_by { |entry| -entry[:amount] }
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

  def conference_player_json(student_season, college_season)
    player_json(student_season).merge(
      college: { id: college_season.college.id, name: college_season.college.name },
      coached_by_us: college_season.coach_id.present?
    )
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
      preseason: all_american.preseason
    }
  end

  def extreme(our_teams, field, lowest: false)
    candidates = our_teams.select { |t| t[field].present? }
    return nil if candidates.empty?

    chosen = lowest ? candidates.min_by { |t| t[field] } : candidates.max_by { |t| t[field] }
    { college: chosen[:college], value: chosen[field] }
  end
end
