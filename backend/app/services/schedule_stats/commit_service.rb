module ScheduleStats
  # Persists a (possibly user-edited) week schedule extraction: finds-or-
  # creates each Game shown (every matchup, not just coached teams' —
  # Colleges are league context even when not coached, per CLAUDE.md) and
  # upserts CollegeGameStat.final_score when a result was read, the same
  # partial-upsert pattern GameStats::CommitService uses for box scores.
  #
  # Never overwrites an existing Game#time with nil just because this
  # round's screenshot happened to show a final score instead of a kickoff
  # time (that's simply what an already-played game's row looks like) —
  # only a freshly-read time value replaces it.
  #
  # Each row commits in its own transaction and a validation failure (e.g.
  # the Game "one game per week per college" check) is caught and reported
  # as a warning rather than aborting the rest of the week's schedule,
  # mirroring RankingStats::CommitService.
  class CommitService
    def initialize(week)
      @week = week
      @season_year = week.season.year
    end

    def call(rows)
      Array(rows).filter_map do |row|
        symbolized = row.deep_symbolize_keys
        commit_row(symbolized)
        nil
      rescue ActiveRecord::RecordInvalid => e
        { matchup: "#{symbolized[:away_raw_name]} at #{symbolized[:home_raw_name]}", error: e.message }
      end
    end

    private

    def commit_row(row)
      away = College.find_by(id: row[:away_college_id])
      home = College.find_by(id: row[:home_college_id])
      return unless away && home

      ActiveRecord::Base.transaction do
        game = find_or_create_game(away, home)
        update_time(game, row[:month], row[:day], row[:time_of_day])
        update_score(game, away, row[:away_score])
        update_score(game, home, row[:home_score])
      end
    end

    def find_or_create_game(away, home)
      Game.find_by(
        week: @week,
        home_college_id: [ home.id, away.id ],
        away_college_id: [ home.id, away.id ]
      ) || Game.create!(week: @week, home_college: home, away_college: away)
    end

    def update_time(game, month, day, time_of_day)
      return if month.blank? || day.blank? || time_of_day.blank?

      match = time_of_day.match(/(\d{1,2}):(\d{2})\s*(AM|PM)/i)
      return unless match

      hour = match[1].to_i % 12
      hour += 12 if match[3].casecmp?("PM")
      # Bowl weeks (post-season) can fall in January of the calendar year after the season's start year.
      year = month.to_i == 1 && @week.post_season? ? @season_year + 1 : @season_year
      game.update!(time: Time.new(year, month, day, hour, match[2].to_i))
    rescue ArgumentError
      nil
    end

    def update_score(game, college, score)
      return if score.blank?

      stat = CollegeGameStat.find_or_initialize_by(game: game, college: college)
      stat.update!(final_score: score)
    end
  end
end
