module RankingStats
  # Persists a (possibly user-edited) Top 25 extraction for one week: upserts
  # CollegeWeekRanking, backfills last week's ranking if it's missing,
  # updates CollegeSeason win/loss records, and finds-or-creates the Games
  # implied by each team's "this week" and "last week" opponent — updating
  # last week's score via CollegeGameStat the same way GameStats::CommitService
  # upserts box-score stats. Each row commits in its own transaction so one
  # bad row (e.g. an unresolved college) doesn't block the other 24.
  class CommitService
    def initialize(week)
      @week = week
      @season = week.season
    end

    # Returns a list of { rank:, error: } for any row that failed to commit
    # (e.g. a Game validation conflict) — every other row still gets its
    # own attempt rather than the whole batch aborting on one bad row.
    def call(rows)
      Array(rows).filter_map do |row|
        symbolized = row.deep_symbolize_keys
        commit_row(symbolized)
        nil
      rescue ActiveRecord::RecordInvalid => e
        { rank: symbolized[:rank], error: e.message }
      end
    end

    private

    def commit_row(row)
      college = College.find_by(id: row[:college_id])
      return unless college && row[:rank]

      ActiveRecord::Base.transaction do
        upsert_ranking(college, row[:rank])
        backfill_last_week_ranking(college, row[:lw_ranking])
        update_college_season(college, row[:wins], row[:losses])
        handle_this_week(college, row[:this_week])
        handle_last_week(college, row[:last_week])
      end
    end

    def upsert_ranking(college, rank)
      ranking = CollegeWeekRanking.find_or_initialize_by(college: college, week: @week)
      ranking.update!(ranking: rank)
    end

    def backfill_last_week_ranking(college, lw_ranking)
      return if lw_ranking.blank? || previous_week.blank?

      CollegeWeekRanking.find_or_create_by!(college: college, week: previous_week) do |ranking|
        ranking.ranking = lw_ranking
      end
    end

    def update_college_season(college, wins, losses)
      return if wins.blank? || losses.blank?

      CollegeSeason.find_by(college: college, season: @season)&.update!(wins: wins, losses: losses)
    end

    def handle_this_week(college, this_week)
      opponent = College.find_by(id: this_week&.dig(:opponent_college_id))
      return unless opponent

      find_or_create_game(@week, college, opponent, this_week[:is_away])
    end

    def handle_last_week(college, last_week)
      opponent = College.find_by(id: last_week&.dig(:opponent_college_id))
      return unless opponent && previous_week

      game = find_or_create_game(previous_week, college, opponent, last_week[:is_away])
      update_score(game, college, last_week[:team_score])
      update_score(game, opponent, last_week[:opponent_score])
    end

    def find_or_create_game(week, team, opponent, is_away)
      home, away = is_away ? [ opponent, team ] : [ team, opponent ]

      Game.find_by(
        week: week,
        home_college_id: [ home.id, away.id ],
        away_college_id: [ home.id, away.id ]
      ) || Game.create!(week: week, home_college: home, away_college: away)
    end

    def update_score(game, college, score)
      return if score.blank?

      stat = CollegeGameStat.find_or_initialize_by(game: game, college: college)
      stat.update!(final_score: score)
    end

    def previous_week
      @previous_week ||= Week.find_by(season: @season, number: @week.number - 1)
    end
  end
end
