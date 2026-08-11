module PlayersOfTheWeek
  # The Player of the Week screen never shows the winner's own team name as
  # text (only a logo), but it does show that team's result for the week as
  # text: an opponent name and a final score (e.g. "vs FCS Southeast (W
  # 27-20)"). If that exact game is already in our DB, the opponent is one
  # side of it and the score tells us which — so the winner's college is
  # simply the other side. If no matching Game exists (most likely because
  # neither side is a coached team we've recorded results for), this
  # returns nil and the row is left "Unmatched" for manual selection, same
  # as the Heisman/All-American flows.
  class GameCollegeResolver
    include CollegeMatching

    def initialize(week)
      @week = week
    end

    def resolve(opponent_raw_name:, opponent_matched_name:, team_score:, opponent_score:)
      opponent_college = resolve_college(opponent_raw_name, opponent_matched_name)
      return nil if opponent_college.blank? || team_score.blank? || opponent_score.blank?

      game = games_for_college(opponent_college.id).find do |candidate|
        scores = final_scores(candidate)
        next false unless scores

        opponent_side_score = candidate.home_college_id == opponent_college.id ? scores[:home] : scores[:away]
        team_side_score = candidate.home_college_id == opponent_college.id ? scores[:away] : scores[:home]
        opponent_side_score == opponent_score && team_side_score == team_score
      end
      return nil unless game

      game.home_college_id == opponent_college.id ? game.away_college : game.home_college
    end

    private

    def games_for_college(college_id)
      Game.where(week_id: @week.id)
          .where("home_college_id = :id OR away_college_id = :id", id: college_id)
          .includes(:college_game_stats)
    end

    def final_scores(game)
      stats = game.college_game_stats.index_by(&:college_id)
      home_stat = stats[game.home_college_id]
      away_stat = stats[game.away_college_id]
      return nil unless home_stat&.final_score && away_stat&.final_score

      { home: home_stat.final_score, away: away_stat.final_score }
    end
  end
end
