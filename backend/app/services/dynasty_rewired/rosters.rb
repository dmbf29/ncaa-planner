module DynastyRewired
  # Imports a school's roster from Dynasty Rewired's roster capture: players already on the roster get their
  # ratings, height and weight refreshed (and Dynasty Rewired's player id saved, which its transfer portal data uses), and players the roster doesn't have yet are created. That is the
  # whole start-of-season import (every roster starts empty) as well as the in-season refresh. Players are
  # matched to roster spots by name; anyone who matches more than one player is listed instead of guessed.
  #
  # What the API gives and what it doesn't:
  # - Position: the API says OL/DL/LB/S but each player's numeric `positionCode` is EA's exact position
  #   (POSITIONS), so created players get LT/RT/MIKE/... directly. Existing players' positions are never touched.
  # - Class year: FR/SO/JR/SR with no redshirt flag. A created player who was on a roster last season gets it
  #   from that: redshirted already, or the same tier as last year, means "(RS)" (checked against all 8,442
  #   returning 2028 players); one with no history gets the plain tier. Existing players' class years are
  #   never touched.
  # - Returning players are linked to last season's Student (same full name, a legal class-year step, an
  #   overall within MAX_OVERALL_JUMP, not already on a roster this season), so their history carries over.
  #
  # A school is one API call, so a whole season is ~140 calls: run it a school at a time (the roster is
  # cached for a few minutes so checking and then importing a school costs one call).
  class Rosters
    POSITIONS = %w[QB HB FB WR TE LT LG C RG RT LEDG REDG DT SAM MIKE WILL CB FS SS K P].freeze
    TIERS = %w[FR SO JR SR].freeze
    MAX_OVERALL_JUMP = 15
    ROSTER_CACHE_TTL = 20.minutes

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
      ratings: ->(p) { p["ratings"].presence },
      dynasty_rewired_player_id: ->(p) { p["playerId"]&.to_s }
    }.freeze

    # updates: [{ student_season:, changes: }]; creates: [{ player:, name:, position:, class_year:, student:, from: }];
    # skipped: [{ name:, reason: }]; missing: names on our roster the API doesn't have (usually a misspelling).
    School = Struct.new(:college_season, :name, :updates, :creates, :unchanged, :skipped, :missing, keyword_init: true)

    def initialize(season, client: Client.new, colleges: CollegeLookup.new)
      @season = season
      @client = client
      @colleges = colleges
    end

    # Schools the API has a roster for that we have a college for: [{ name:, team_id:, college_season: }].
    def schools
      captured_schools.filter_map do |school|
        college = @colleges.find(school["name"]) or next
        college_season = CollegeSeason.find_by(season: @season, college: college) or next

        { name: college.name, team_id: school["teamId"], college_season: college_season }
      end
    end

    # What importing every school (or just the colleges named in `only`) would change. Nothing is saved.
    def plan(only: nil)
      names = Array(only).map { |name| name.to_s.downcase } if only
      schools.filter_map { |school| plan_school(school) if names.nil? || names.include?(school[:name].downcase) }
    end

    def plan_school(school)
      roster = Rails.cache.fetch("dynasty_rewired/roster/#{@season.year}/#{school[:team_id]}", expires_in: ROSTER_CACHE_TTL) do
        @client.roster(@season.year, school[:team_id])
      end
      school_plan(school[:college_season], school[:name], roster)
    end

    # One school by name and the API's team id (as listed by #schools), for importing a school at a time.
    def refresh(name:, team_id:, apply: false)
      college = @colleges.find(name) or raise ActiveRecord::RecordNotFound, "No college named #{name}"
      college_season = CollegeSeason.find_by!(season: @season, college: college)
      school = plan_school(name: college.name, team_id: team_id, college_season: college_season)
      self.class.commit([ school ]) if apply
      school
    end

    # Writes every planned update and creation in one transaction; returns how many players were written.
    def self.commit(schools)
      StudentSeason.transaction do
        schools.sum do |school|
          school.updates.each { |update| update[:student_season].update!(update[:changes]) }
          school.creates.each { |creation| create_player(school.college_season, creation) }
          school.updates.size + school.creates.size
        end
      end
    end

    def self.create_player(college_season, creation)
      player = creation[:player]
      student = creation[:student] || Student.create!(first_name: player["firstName"], last_name: player["lastName"])
      student_season = student.student_seasons.find_or_initialize_by(college_season: college_season)
      student_season.assign_attributes(creation.slice(:position, :class_year))
      student_season.assign_attributes(COLUMNS.transform_values { |read| read.call(player) }.compact)
      student_season.save!
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
      school = School.new(college_season: college_season, name: name, updates: [], creates: [], unchanged: 0, skipped: [], missing: [])

      theirs.each do |key, players|
        mine = ours[key] || []
        if mine.one? && players.one? then record(school, mine.first, players.first)
        elsif mine.empty? && players.one? then plan_creation(school, players.first)
        else school.skipped << { name: players.first["name"], reason: "several players share this name" }
        end
      end
      school.missing = (ours.keys - theirs.keys).map { |key| ours[key].first.student.name }
      school
    end

    def record(school, student_season, player)
      incoming = COLUMNS.transform_values { |read| read.call(player) }.compact
      changes = incoming.reject { |column, value| student_season[column] == value }
      return school.unchanged += 1 if changes.empty?

      school.updates << { student_season: student_season, changes: changes }
    end

    def plan_creation(school, player)
      position = POSITIONS[player["positionCode"].to_i] if player["positionCode"]
      tier = player["year"]
      return school.skipped << { name: player["name"], reason: "unknown position" } unless position
      return school.skipped << { name: player["name"], reason: "unknown class year #{tier.inspect}" } unless TIERS.include?(tier)

      returning = last_season_matches(player, tier)
      return school.skipped << { name: player["name"], reason: "several players from last season fit" } if returning.many?

      previous = returning.first
      school.creates << {
        player: player, name: player["name"], position: position, class_year: class_year_for(tier, previous),
        student: previous&.student, from: previous&.college_season&.college&.name
      }
    end

    # Redshirted last season or the same tier as last season (a redshirt just taken) means "(RS)"; moving up a
    # tier without a redshirt, or no history at all, is the plain tier.
    def class_year_for(tier, previous)
      return tier unless previous

      redshirt = previous.class_year.include?("(RS)") || TIERS.index(tier) == TIERS.index(previous.class_year.sub("(RS)", ""))
      redshirt ? "#{tier}(RS)" : tier
    end

    # Last season's players league-wide (a transfer keeps their record) with this full name, a class year that
    # legally leads to `tier`, a similar overall, and not already on a roster this season.
    def last_season_matches(player, tier)
      previous_season = @season.previous_season or return []
      name = self.class.normalize(player["name"])

      StudentSeason.joins(:student, :college_season)
                   .where(college_seasons: { season_id: previous_season.id })
                   .where("lower(students.last_name) = ?", player["lastName"].to_s.downcase)
                   .includes(:student, college_season: :college)
                   .select do |ss|
        self.class.normalize(ss.student.name) == name && legal_step?(ss.class_year, tier) &&
          (ss.overall.nil? || player["overall"].nil? || (ss.overall - player["overall"]).abs <= MAX_OVERALL_JUMP) &&
          !on_a_roster_this_season?(ss.student_id)
      end
    end

    # One tier up, or the same tier when no redshirt has been taken yet.
    def legal_step?(previous_class_year, tier)
      previous = TIERS.index(previous_class_year.sub("(RS)", ""))
      current = TIERS.index(tier)
      return false unless previous

      current == previous + 1 || (current == previous && !previous_class_year.include?("(RS)"))
    end

    def on_a_roster_this_season?(student_id)
      StudentSeason.joins(:college_season).exists?(student_id: student_id, college_seasons: { season_id: @season.id })
    end
  end
end
