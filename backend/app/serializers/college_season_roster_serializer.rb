# The full roster for one CollegeSeason — every StudentSeason, grouped by
# CollegeSeason::POSITION_GROUPS and sorted by overall within each group —
# what a coach means by "the students for that college season."
class CollegeSeasonRosterSerializer
  # Same class-year buckets the user's old spreadsheet used: redshirt
  # upperclassmen fold into their base year (SR(RS) -> SR), but a redshirt
  # freshman is kept distinct from a true freshman since that's a real
  # eligibility difference worth seeing at a glance.
  CLASS_BUCKETS = [ "SR", "JR", "SO", "FR(RS)", "FR" ].freeze

  def initialize(college_season)
    @college_season = college_season
  end

  def as_json
    {
      college_season: {
        id: @college_season.id,
        college: { id: @college_season.college.id, name: @college_season.college.name },
        coach: @college_season.coach && { id: @college_season.coach.id, name: @college_season.coach.name },
        season: { id: @college_season.season.id, year: @college_season.season.year }
      },
      class_breakdown: class_breakdown_json,
      position_groups: CollegeSeason::POSITION_GROUPS.map { |group, positions| group_json(group, positions) },
      games: games_json
    }
  end

  private

  def student_seasons
    @student_seasons ||= @college_season.student_seasons.includes(:student, injuries: { game: :week }).to_a
  end

  # Already-played games only — the game picker for reporting an injury
  # only makes sense against something that actually happened.
  def games_json
    @college_season.games.select(&:played?).sort_by { |g| g.week.number }.map do |game|
      home = game.home_college_id == @college_season.college_id
      opponent = home ? game.away_college : game.home_college
      { id: game.id, week_number: game.week.number, opponent: opponent.name, home: home }
    end
  end

  def class_bucket(class_year)
    return class_year if CLASS_BUCKETS.include?(class_year)

    class_year.delete_suffix("(RS)")
  end

  def class_breakdown_json
    counts = student_seasons.each_with_object(Hash.new(0)) { |ss, h| h[class_bucket(ss.class_year)] += 1 }

    {
      total: student_seasons.size,
      buckets: CLASS_BUCKETS.map { |bucket| { bucket: bucket, count: counts[bucket] } }
    }
  end

  def group_json(group, positions)
    players = student_seasons.select { |ss| positions.include?(ss.position) }
                              .sort_by { |ss| -(ss.overall || -1) }
    overalls = players.filter_map(&:overall)
    speeds = players.filter_map(&:speed)

    {
      position_group: group,
      average_overall: average(overalls),
      high_overall: overalls.max,
      low_overall: overalls.min,
      average_speed: average(speeds),
      players: players.map { |ss| player_json(ss) }
    }
  end

  def average(values)
    return nil if values.empty?

    (values.sum.to_f / values.size).round
  end

  def player_json(student_season)
    {
      id: student_season.id,
      name: student_season.student.name,
      position: student_season.position,
      class_year: student_season.class_year,
      overall: student_season.overall,
      dev_trait: student_season.dev_trait,
      speed: student_season.speed,
      nil_amount: student_season.nil_amount,
      injuries: student_season.injuries.map { |injury| injury_json(injury) }
    }
  end

  def injury_json(injury)
    {
      id: injury.id,
      game_id: injury.game_id,
      description: injury.description,
      weeks_out: injury.weeks_out,
      return_week_number: injury.return_week_number,
      out_for_season: injury.out_for_season?
    }
  end
end
