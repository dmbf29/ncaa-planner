module BigGameBreakdown
  # The hosts' running record on their Big Game Breakdown picks, graded from
  # final scores on read (nothing about a result is stored on the pick, same
  # as the other derived numbers in the app).
  class Scorecard
    def initialize(season)
      @season = season
    end

    # { "Arlis" => { wins:, losses:, pushes: }, ... } across every graded
    # pick in weeks up to and including `through_week_number`.
    def record(through_week_number:)
      picks = picks_in_weeks { |number| number <= through_week_number }
      picks.each_with_object(Hash.new { |hash, host| hash[host] = { wins: 0, losses: 0, pushes: 0 } }) do |pick, record|
        case pick.result
        when :win then record[pick.host][:wins] += 1
        when :loss then record[pick.host][:losses] += 1
        when :push then record[pick.host][:pushes] += 1
        end
      end.to_h
    end

    # Each pick made for one week's games, with its result (nil if the game
    # hasn't been played), grouped game by game.
    def week_results(week_number)
      picks = picks_in_weeks { |number| number == week_number }
      picks.group_by(&:game).map do |game, game_picks|
        {
          game_id: game.id,
          home: game.home_college.name,
          away: game.away_college.name,
          picks: game_picks.map { |pick| { host: pick.host, bet: pick.description, result: pick.result } }
        }
      end
    end

    private

    def picks_in_weeks
      GamePick.joins(game: :week)
              .where(weeks: { season_id: @season.id })
              .includes(game: %i[week home_college away_college college_game_stats])
              .order(:id)
              .select { |pick| yield pick.game.week.number }
    end
  end
end
