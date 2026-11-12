module Scheduling
  # Everything the commissioner's scheduling screens show for a season: the bye weeks and, for each coached team, one
  # slot per week 0-13 (fixed game, bye, or open with how many possible opponents are registered and how many ranked).
  class Overview
    def initialize(season)
      @season = season
    end

    def as_json(*)
      weeks = @season.weeks.where(number: Rules::WEEK_NUMBERS).order(:number).to_a
      {
        season_id: @season.id,
        bye_week_numbers: @season.schedule_bye_week_numbers,
        weeks: weeks.map { |week| { id: week.id, number: week.number } },
        teams: coached_college_seasons.map { |college_season| team_json(college_season, weeks) }
      }
    end

    private

    def coached_college_seasons
      @season.college_seasons.where.not(coach_id: nil).includes(:college, :coach, :schedule_options).sort_by { |cs| cs.college.name }
    end

    def team_json(college_season, weeks)
      college = college_season.college
      games = Game.where(week_id: weeks.map(&:id)).where("home_college_id = :id OR away_college_id = :id", id: college.id)
                  .includes(:home_college, :away_college).index_by(&:week_id)
      locked = college_season.schedule_locked_week_ids

      {
        id: college_season.id,
        college: { id: college.id, name: college.name },
        coach: college_season.coach&.name,
        uploaded: college_season.schedule_uploaded_at.present?,
        confirmed: college_season.schedule_confirmed_at.present?,
        schedule_token: college_season.schedule_token,
        road_games_required: Rules.road_games_required(college_season),
        slots: weeks.map { |week| slot_json(week, college, college_season, games[week.id], locked.include?(week.id)) }
      }
    end

    def slot_json(week, college, college_season, game, locked)
      return { week_id: week.id, week_number: week.number, state: "bye" } if @season.schedule_bye_week_numbers.include?(week.number)

      if locked && game
        away = game.away_college_id == college.id
        opponent = away ? game.home_college : game.away_college
        return { week_id: week.id, week_number: week.number, state: "locked", is_away: away, opponent: { id: opponent.id, name: opponent.name } }
      end

      options = college_season.schedule_options.select { |option| option.week_id == week.id }
      { week_id: week.id, week_number: week.number, state: "open", option_count: options.size, ranked_count: options.count(&:rank) }
    end
  end
end
