module Scheduling
  # What a coach sees on their share-link page: their own grid with the opponents they can pick for each open week (each
  # tagged ok / warning / blocked by PickRules), whether they can confirm yet, and everyone else's schedules read-only.
  class CoachView
    def initialize(college_season)
      @cs = college_season
      @season = college_season.season
      @rules = PickRules.new(college_season)
    end

    def as_json(*)
      overview = Overview.new(@season)
      team = overview.public_teams.find { |t| t[:id] == @cs.id }
      {
        season: { id: @season.id, year: @season.year },
        team: team,
        bye_week_numbers: @season.schedule_bye_week_numbers,
        road_games_required: @rules.road_required,
        road_games: @rules.road_count,
        problems: @rules.confirmable_problems,
        confirmed: @cs.schedule_confirmed_at.present?,
        options: options_by_week,
        other_teams: overview.public_teams.reject { |t| t[:id] == @cs.id }
      }
    end

    private

    def options_by_week
      ratings = @season.college_seasons.index_by(&:college_id)
      weeks = @season.weeks.index_by(&:id)
      @cs.schedule_options.includes(:opponent_college).group_by(&:week_id).to_h do |week_id, options|
        week = weeks[week_id]
        [ week.number, options.map { |option| option_json(option, week, ratings[option.opponent_college_id]) }.sort_by { |o| order_key(o) } ]
      end
    end

    def option_json(option, week, rating)
      verdict = @rules.evaluate(week, option.opponent_college_id)
      {
        college: { id: option.opponent_college.id, name: option.opponent_college.name },
        rank: option.rank, ranked: option.ranked, suggested: option.suggested,
        overall: rating&.overall, offense: rating&.offense, defense: rating&.defense, prestige: rating&.prestige,
        status: verdict[:status], reasons: verdict[:reasons]
      }
    end

    def order_key(option)
      [ option[:status] == :blocked ? 1 : 0, -(option[:overall] || 0), option[:college][:name] ]
    end
  end
end
