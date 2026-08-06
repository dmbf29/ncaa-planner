# The full roster for one CollegeSeason — every StudentSeason, grouped by
# CollegeSeason::POSITION_GROUPS and sorted by overall within each group —
# what a coach means by "the students for that college season."
class CollegeSeasonRosterSerializer
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
      position_groups: CollegeSeason::POSITION_GROUPS.map { |group, positions| group_json(group, positions) }
    }
  end

  private

  def student_seasons
    @student_seasons ||= @college_season.student_seasons.includes(:student).to_a
  end

  def group_json(group, positions)
    players = student_seasons.select { |ss| positions.include?(ss.position) }
                              .sort_by { |ss| -(ss.overall || -1) }
    { position_group: group, players: players.map { |ss| player_json(ss) } }
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
      nil_amount: student_season.nil_amount
    }
  end
end
