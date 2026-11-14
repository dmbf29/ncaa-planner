module DynastyRewired
  # Refreshes the ratings of players already on a school's roster from Dynasty Rewired's roster
  # capture. Players are matched to roster spots by name; position and class year are never touched
  # (the API only knows OL/DL/LB/S and has no redshirt flag), and nobody is created or removed. A name
  # that doesn't match exactly one player on each side is listed instead of guessed.
  #
  # A school is one API call, so a whole season is ~140 calls: run it a few schools at a time or accept
  # that it takes a couple of minutes.
  class Rosters
    # our column => how to read it from an API player
    COLUMNS = {
      overall: ->(p) { p["overall"] },
      speed: ->(p) { p["speed"] },
      acceleration: ->(p) { p.dig("ratings", "PACC") },
      agility: ->(p) { p.dig("ratings", "PAGI") },
      change_of_direction: ->(p) { p.dig("ratings", "CODR") },
      strength: ->(p) { p.dig("ratings", "PSTR") },
      awareness: ->(p) { p.dig("ratings", "PAWR") },
      height_inches: ->(p) { p["heightInches"] },
      weight_lbs: ->(p) { p["weightPounds"] },
      ratings: ->(p) { p["ratings"].presence }
    }.freeze

    School = Struct.new(:college_season, :name, :updates, :unchanged, :unmatched, :ambiguous, :missing, keyword_init: true)

    def initialize(season, client: Client.new, colleges: CollegeLookup.new)
      @season = season
      @client = client
      @colleges = colleges
    end

    # Schools the API has a roster for that we also have a roster for: [{ name:, team_id:, college_season: }].
    def schools
      captured_schools.filter_map do |school|
        college = @colleges.find(school["name"]) or next
        college_season = CollegeSeason.find_by(season: @season, college: college)
        next unless college_season&.student_seasons&.exists?

        { name: college.name, team_id: school["teamId"], college_season: college_season }
      end
    end

    # What refreshing every school (or just the colleges named in `only`) would change. Nothing is saved.
    def plan(only: nil)
      names = Array(only).map { |name| name.to_s.downcase } if only
      schools.filter_map { |school| plan_school(school) if names.nil? || names.include?(school[:name].downcase) }
    end

    def plan_school(school)
      school_plan(school[:college_season], school[:name], @client.roster(@season.year, school[:team_id]))
    end

    # One school by name and the API's team id (as listed by #schools), for refreshing a school at a time.
    def refresh(name:, team_id:, apply: false)
      college = @colleges.find(name) or raise ActiveRecord::RecordNotFound, "No college named #{name}"
      college_season = CollegeSeason.find_by!(season: @season, college: college)
      school = plan_school(name: college.name, team_id: team_id, college_season: college_season)
      self.class.commit([ school ]) if apply
      school
    end

    # Writes every planned change in one transaction; returns how many players were updated.
    def self.commit(schools)
      StudentSeason.transaction do
        schools.sum do |school|
          school.updates.each { |update| update[:student_season].update!(update[:changes]) }.size
        end
      end
    end

    def self.normalize(name)
      BoxScoreMapper.normalize(name)
    end

    private

    def captured_schools
      @client.rosters(@season.year)["runs"].flat_map { |run| run["schools"] }.uniq { |school| school["teamId"] }
    end

    def school_plan(college_season, name, roster)
      ours = college_season.student_seasons.includes(:student).group_by { |ss| self.class.normalize(ss.student.name) }
      theirs = roster["players"].group_by { |player| self.class.normalize(player["name"]) }
      school = School.new(college_season: college_season, name: name, updates: [], unchanged: 0, unmatched: [], ambiguous: [], missing: [])

      theirs.each do |key, players|
        mine = ours[key] || []
        if mine.one? && players.one? then record(school, mine.first, players.first)
        elsif mine.empty? then school.unmatched.concat(players.map { |p| p["name"] })
        else school.ambiguous.concat(players.map { |p| p["name"] }.uniq)
        end
      end
      school.missing = (ours.keys - theirs.keys).map { |key| ours[key].first.student.name }
      school
    end

    def record(school, student_season, player)
      incoming = COLUMNS.transform_values { |read| read.call(player) }.compact
      changes = incoming.reject { |column, value| student_season[column] == value }
      return school.unchanged += 1 if changes.empty?

      school.updates << { student_season: student_season, changes: changes, before: student_season.slice(*changes.keys.excluding(:ratings)) }
    end
  end
end
