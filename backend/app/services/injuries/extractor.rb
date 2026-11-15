module Injuries
  # Reads the game's league-wide injury report screen (NAME / POS / OVR / INJURY / LENGTH / STATUS, with the team
  # name in the top-left selector) and turns it into proposed Injury rows for review.
  #
  # One call per screenshot: the team name plus every row. Rows are resolved to a StudentSeason on that team's
  # roster for this season by (first initial, last name, position) — the screen only shows "D.Harold" — falling
  # back to ignoring position when nothing matches. Unmatched rows stay in the review with no player picked.
  #
  # There's no game on this screen, and none is needed: a player appears here the week after getting hurt, and
  # LENGTH is the weeks remaining then, so an injury with no earlier record is anchored to the team's most recently
  # played game (see Injury#return_week_number). A player who already has an injury with the same description this
  # season is flagged as a duplicate and left unchecked, so re-uploading the same report doesn't double-register.
  class Extractor
    include CollegeMatching

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an expert at reading college football video game injury report screenshots and transcribing the
      exact values shown. Only report a value if you can actually see it — never guess.
    PROMPT

    def initialize(season)
      @season = season
    end

    def call(images)
      return { rows: [], teams: [] } if images.blank?

      rows = Array(images).flat_map { |image| extract_image(image) }
      rows = rows.uniq { |row| [ row[:college_id], row[:raw_name], row[:description] ] }
      team_ids = rows.filter_map { |row| row[:college_id] }.uniq

      { rows: rows, teams: team_ids.filter_map { |id| team_json(id) } }
    end

    private

    def extract_image(image)
      raw = RubyLLM.chat.with_instructions(SYSTEM_PROMPT).with_schema(schema).ask(prompt, with: [ image ]).content
      college = resolve_college(raw["team_raw_name"], raw["team_name"])
      Array(raw["injuries"]).select { |row| row.is_a?(Hash) }.map { |row| build_row(row, college, raw["team_raw_name"]) }
    end

    def schema
      names = college_names
      RubyLLM::Schema.create do
        string :team_raw_name, description: "The team name in the top-left selector, exactly as shown."
        string :team_name, enum: names,
               description: "The database college team_raw_name refers to. Only use '#{UNMATCHED}' if none of the options are a plausible match."
        array :injuries, description: "One entry per player row, top to bottom." do
          object do
            string :name, description: "The NAME column exactly as shown, e.g. 'D.Harold'."
            string :position, description: "The POS column, e.g. 'DT'."
            string :description, description: "The INJURY column exactly as shown, e.g. 'Complete PCL Tear'."
            integer :weeks_out, description: "The LENGTH column, in weeks."
            string :status, description: "The STATUS column exactly as shown, e.g. 'Injured'."
          end
        end
      end
    end

    def prompt
      "This is one screen of a team's injury report. Read the team name from the top-left and every player row."
    end

    def build_row(row, college, team_raw_name)
      base = {
        raw_name: row["name"], position: row["position"], description: row["description"],
        weeks_out: row["weeks_out"], status: row["status"],
        college_id: college&.id, college_raw_name: team_raw_name
      }
      return base.merge(match_status: "unmatched", student_season_id: nil, game_id: nil, duplicate: false) unless college

      student_season = match_player(college, row["name"], row["position"])
      existing = student_season && existing_injury(student_season, row["description"])
      base.merge(
        student_season_id: student_season&.id,
        match_status: student_season ? "matched" : "unmatched",
        game_id: latest_game(college)&.id,
        duplicate: existing.present?
      )
    end

    def roster(college)
      @rosters ||= {}
      @rosters[college.id] ||= begin
        college_season = CollegeSeason.find_by(college: college, season: @season)
        college_season ? college_season.student_seasons.includes(:student, :injuries).to_a : []
      end
    end

    def match_player(college, raw_name, position)
      initial, last = split_name(raw_name)
      return nil if last.blank?

      by_name = roster(college).select do |ss|
        _, roster_last = split_name("#{ss.student.first_name[0]}.#{ss.student.last_name}")
        roster_last == last && ss.student.first_name.to_s.strip[0].to_s.downcase == initial
      end
      by_name.find { |ss| PositionBoardMapping.canonical(ss.position) == PositionBoardMapping.canonical(position) } || by_name.first
    end

    # "D.Harold" -> ["d", "harold"]; trailing suffixes and punctuation are ignored on both sides.
    def split_name(name)
      initial, last = name.to_s.strip.split(".", 2)
      last = last.to_s.split(/\s+/).reject { |part| Student::NAME_SUFFIXES.include?(part) }.join
      [ initial.to_s.strip[0].to_s.downcase, last.downcase.gsub(/[^a-z0-9]/, "") ]
    end

    def existing_injury(student_season, description)
      student_season.injuries.find { |injury| Student.match_key(injury.description) == Student.match_key(description) }
    end

    def played_games(college)
      college_season = CollegeSeason.find_by(college: college, season: @season)
      return [] unless college_season

      college_season.games.select(&:played?).sort_by { |game| game.week.number }
    end

    def latest_game(college)
      played_games(college).last
    end

    def team_json(college_id)
      college = colleges.find { |c| c.id == college_id }
      {
        college_id: college.id,
        college_name: college.name,
        players: roster(college).sort_by { |ss| ss.student.last_name.to_s }.map do |ss|
          { student_season_id: ss.id, name: ss.student.name, position: ss.position }
        end,
        games: played_games(college).map do |game|
          opponent = game.home_college_id == college.id ? game.away_college : game.home_college
          { id: game.id, week_number: game.week.number, opponent: opponent.name, home: game.home_college_id == college.id }
        end
      }
    end
  end
end
