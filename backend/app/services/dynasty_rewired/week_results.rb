module DynastyRewired
  # Final scores for one regular-season week from the schedule dataset, matched to our Game rows. A
  # game with no saved score gets a CollegeGameStat holding just final_score, which is all we keep for
  # games no user coach played. Nothing already saved is overwritten: a score that disagrees with ours
  # is returned in `conflicts` for review instead. "Bowl Week N" is our week 15 + N (Season#create_weeks
  # numbers them 16-19). Bowl games are only matched to games already in the season, never created, so
  # a final bowl game we haven't set up yet comes back in `unmatched`.
  class WeekResults
    Result = Struct.new(:week_number, :new_scores, :same, :conflicts, :unmatched, :not_final, keyword_init: true)

    BOWL_WEEK_OFFSET = 15

    def self.week_number(label)
      label.to_s[/\AWeek (\d+)\z/, 1]&.to_i
    end

    # Like week_number, but "Bowl Week N" counts too. Rankings still use week_number: their weeks differ.
    def self.game_week_number(label)
      week_number(label) || label.to_s[/\ABowl Week (\d+)\z/, 1]&.to_i&.+(BOWL_WEEK_OFFSET)
    end

    def initialize(schedule_week, season:, colleges: CollegeLookup.new)
      @week_data = schedule_week
      @season = season
      @colleges = colleges
    end

    def call
      number = self.class.game_week_number(@week_data["label"]) or raise ArgumentError, "#{@week_data['label']} isn't a game week"
      result = Result.new(week_number: number, new_scores: [], same: [], conflicts: [], unmatched: [], not_final: [])
      week = @season.weeks.find_by!(number: number)
      games = Game.where(week: week).index_by { |game| [ game.home_college_id, game.away_college_id ] }
      saved = CollegeGameStat.where(game_id: games.values.map(&:id)).pluck(:game_id, :college_id, :final_score).to_h { |g, c, s| [ [ g, c ], s ] }
      built = {}

      @week_data["games"].each do |game|
        next result.not_final << game unless game["status"] == "final"

        home = @colleges.find(game["homeName"])
        away = @colleges.find(game["awayName"])
        ours = home && away && (games[[ home.id, away.id ]] || new_bowl_game(week, home, away, games, built))
        next result.unmatched << game unless ours

        { home => game["homeScore"], away => game["awayScore"] }.each do |college, score|
          existing = saved[[ ours.id, college.id ]]
          row = { game: ours, college: college, score: score, saved: existing, label: "#{game['awayName']} @ #{game['homeName']}" }
          (existing.nil? ? result.new_scores : existing == score ? result.same : result.conflicts) << row
        end
      end
      result
    end

    # A final bowl game we don't have yet is built (not saved) so its scores can be reviewed and saved
    # with it; the bowl name and CFP round come later from the postseason bracket. Only when neither
    # team already has a game that week, so a matchup that disagrees with one we saved isn't duplicated.
    def new_bowl_game(week, home, away, games, built)
      return unless week.number > BOWL_WEEK_OFFSET
      return if games.keys.flatten.intersect?([ home.id, away.id ])

      built[[ home.id, away.id ]] ||= Game.new(week: week, home_college: home, away_college: away)
    end
    private :new_bowl_game

    def self.commit(rows)
      ActiveRecord::Base.transaction do
        rows.each do |row|
          row[:game].save! if row[:game].new_record?
          CollegeGameStat.find_or_initialize_by(game: row[:game], college: row[:college]).update!(final_score: row[:score])
        end
      end
    end
  end
end
