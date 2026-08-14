module TeamSchedule
  # Persists a (possibly user-edited) team-schedule extraction: updates the
  # team's own win-loss record, prestige, and OVR/OFF/DEF ratings in one
  # shot, then finds-or-creates each week's Game (every row shown — not just
  # the ones with a result, so an upcoming week's kickoff time gets saved
  # too) and upserts CollegeGameStat.final_score when a result was read.
  # Mirrors the partial-upsert pattern GameStats::CommitService and
  # ScheduleStats::CommitService use.
  #
  # A BYE row has no Game (there's nothing to schedule), but the week
  # number is still recorded on CollegeSeason#bye_week_ids — this is the
  # only place in the app that ever sees a real BYE row on screen, so it's
  # the only source of truth for "this week was actually a bye" as opposed
  # to "this week's game just hasn't been uploaded yet." Anywhere that used
  # to treat "no Game found" as an implicit bye now needs to check this
  # list instead, or it can't tell a real bye apart from missing data.
  #
  # Each row commits in its own transaction and a validation failure (e.g.
  # the Game "one game per week per college" check) is caught and reported
  # as a warning rather than aborting the rest of the schedule, mirroring
  # RankingStats::CommitService.
  class CommitService
    def initialize(college_season)
      @college_season = college_season
      @season = college_season.season
    end

    def call(team_stats, rows)
      update_team_stats(team_stats)

      Array(rows).filter_map do |row|
        symbolized = row.deep_symbolize_keys
        commit_row(symbolized)
        nil
      rescue ActiveRecord::RecordInvalid => e
        { week_label: symbolized[:week_label], error: e.message }
      end
    end

    private

    def update_team_stats(stats)
      return if stats.blank?

      updates = stats.slice(:wins, :losses, :prestige, :overall, :offense, :defense).compact
      @college_season.update!(updates) if updates.present?
    end

    def commit_row(row)
      week = @season.weeks.find_by(id: row[:week_id])
      return unless week

      return record_bye(week) if row[:is_bye]

      opponent = College.find_by(id: row[:opponent_college_id])
      return unless opponent

      ActiveRecord::Base.transaction do
        game = find_or_create_game(week, opponent, row[:is_away])
        update_time(game, week, row[:month], row[:day], row[:time_of_day])
        update_score(game, @college_season.college, row[:team_score])
        update_score(game, opponent, row[:opponent_score])
      end
    end

    def record_bye(week)
      return if @college_season.bye_week_ids.include?(week.id)

      @college_season.update!(bye_week_ids: @college_season.bye_week_ids + [ week.id ])
    end

    def find_or_create_game(week, opponent, is_away)
      team = @college_season.college
      home, away = is_away ? [ opponent, team ] : [ team, opponent ]

      Game.find_by(
        week: week,
        home_college_id: [ home.id, away.id ],
        away_college_id: [ home.id, away.id ]
      ) || Game.create!(week: week, home_college: home, away_college: away)
    end

    def update_time(game, week, month, day, time_of_day)
      return if month.blank? || day.blank? || time_of_day.blank?

      match = time_of_day.match(/(\d{1,2}):(\d{2})\s*(AM|PM)/i)
      return unless match

      hour = match[1].to_i % 12
      hour += 12 if match[3].casecmp?("PM")
      # Bowl weeks (post-season) can fall in January of the calendar year after the season's start year.
      year = month.to_i == 1 && week.post_season? ? @season.year + 1 : @season.year
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
