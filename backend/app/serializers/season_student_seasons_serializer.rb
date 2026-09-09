# Every StudentSeason in one Season, flattened across all of its
# college_seasons — the league-wide player pool used for transfer-portal
# searching. This endpoint is read-only: the frontend loads the whole list
# once and does all filtering/sorting in memory, so all this needs to return
# is a flat array of players plus the distinct values that populate the
# filter dropdowns.
#
# ~12k players a season, so this deliberately does NOT instantiate
# ActiveRecord objects — a flat `pluck` over the join builds the same JSON
# roughly 9x faster than loading StudentSeason/Student/CollegeSeason/College
# rows and walking associations.
class SeasonStudentSeasonsSerializer
  include Rails.application.routes.url_helpers

  PLAYER_COLUMNS = [
    "student_seasons.id",
    "students.first_name",
    "students.last_name",
    "student_seasons.position",
    "student_seasons.class_year",
    "student_seasons.overall",
    "student_seasons.speed",
    "student_seasons.acceleration",
    "student_seasons.agility",
    "student_seasons.change_of_direction",
    "student_seasons.strength",
    "student_seasons.awareness",
    "student_seasons.dev_trait",
    "student_seasons.nil_amount",
    "college_seasons.id",
    "colleges.name",
    "college_seasons.conference"
  ].freeze

  def initialize(season)
    @season = season
  end

  def as_json
    {
      season: { id: @season.id, year: @season.year },
      filters: {
        positions: players.map { |p| p[:position] }.uniq.compact.sort,
        class_years: players.map { |p| p[:class_year] }.uniq.compact.sort,
        dev_traits: players.map { |p| p[:dev_trait] }.uniq.compact,
        teams: team_filters
      },
      players: players
    }
  end

  private

  def players
    @players ||= player_rows.map do |row|
      id, first_name, last_name, position, class_year, overall, speed, acceleration,
        agility, change_of_direction, strength, awareness, dev_trait,
        nil_amount, college_season_id, team, conference = row

      {
        id: id,
        name: "#{first_name} #{last_name}".strip,
        position: position,
        class_year: class_year,
        overall: overall,
        speed: speed,
        acceleration: acceleration,
        agility: agility,
        change_of_direction: change_of_direction,
        strength: strength,
        awareness: awareness,
        dev_trait: dev_trait,
        nil_amount: nil_amount,
        college_season_id: college_season_id,
        team: team,
        conference: conference
      }
    end
  end

  def player_rows
    StudentSeason
      .joins(:student, college_season: :college)
      .where(college_seasons: { season_id: @season.id })
      .pluck(*PLAYER_COLUMNS)
  end

  def team_filters
    @season.college_seasons.includes(college: { logo_attachment: :blob }).map do |cs|
      college = cs.college
      {
        college_season_id: cs.id,
        college_id: cs.college_id,
        name: college.name,
        conference: cs.conference,
        coached: cs.coach_id.present?,
        logo_url: (rails_blob_path(college.logo, only_path: true) if college.logo.attached?)
      }
    end.sort_by { |team| team[:name].to_s }
  end
end
