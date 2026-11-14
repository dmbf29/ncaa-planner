module DynastyRewired
  # Turns one Dynasty Rewired box score into the same row shapes GameStats::CommitService takes
  # (college_stats / player_stats), matching each player to a roster StudentSeason by name. Players
  # that can't be matched, or match more than one roster spot, are returned in `unmatched` /
  # `ambiguous` instead of being guessed; CommitService skips any row with no student_season_id.
  class BoxScoreMapper
    Result = Struct.new(:game, :college_stats, :player_stats, :unmatched, :ambiguous, keyword_init: true)

    def initialize(box_score, season:, colleges: CollegeLookup.new)
      @box = box_score
      @season = season
      @colleges = colleges
    end

    def call
      home = @colleges.find(@box.dig("game", "homeName"))
      away = @colleges.find(@box.dig("game", "awayName"))
      game = home && away && Game.joins(:week).find_by(weeks: { season_id: @season.id }, home_college: home, away_college: away)

      Result.new(game: game, college_stats: game ? college_stats(home, away) : [], player_stats: [], unmatched: [], ambiguous: []).tap do |result|
        player_rows(result, "home" => home, "away" => away) if game
      end
    end

    def self.normalize(name)
      name.to_s.downcase.gsub(/[^a-z ]/, "").squeeze(" ").strip
    end

    private

    def college_stats(home, away)
      { "home" => home, "away" => away }.map do |side, college|
        { team: college.name, fields: StatMap::COLLEGE.transform_values { |code| @box.dig(side, code) } }
      end
    end

    def player_rows(result, colleges)
      colleges.each do |side, college|
        roster = StudentSeason.joins(:college_season).where(college_seasons: { college_id: college.id, season_id: @season.id })
                              .includes(:student).group_by { |ss| self.class.normalize(ss.student.name) }
        next if roster.empty? # an opponent we don't coach has no saved roster to match against

        team_id = @box.dig("game", "#{side}TeamId")

        @box["players"].select { |p| p["teamId"] == team_id }.each do |player|
          fields = StatMap::PLAYER.transform_values { |code| player["stats"][code] }
          matches = roster[self.class.normalize(player["name"])] || []
          row = { student_season_id: matches.first&.id, name: player["name"], position: player["position"], team: college.name, fields: fields }

          next result.player_stats << row if matches.one?
          next if GameStats::StatFields.empty_line?(fields)

          (matches.empty? ? result.unmatched : result.ambiguous) << row
        end
      end
    end
  end
end
