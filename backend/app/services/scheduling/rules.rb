module Scheduling
  # The scheduling rules that depend only on a season's setup. Bookings across coaches (no repeat before another
  # coach's week) join this when coaches start choosing their own opponents.
  module Rules
    WEEK_NUMBERS = (0..13).freeze
    MAX_BYES = 2

    # Weeks 0-13 are the ones a coach fills; the commissioner's byes come off the top.
    def self.schedulable_week_numbers(season)
      WEEK_NUMBERS.to_a - season.schedule_bye_week_numbers
    end

    # At least one non-conference road game; the reigning national champion needs two.
    def self.road_games_required(college_season)
      champion_last_season?(college_season) ? 2 : 1
    end

    def self.champion_last_season?(college_season)
      previous = college_season.season.previous_season
      return false unless previous

      final = Game.joins(:week).where(weeks: { season_id: previous.id }, cfp_round: :championship).includes(:college_game_stats).first
      return false unless final&.played?

      winner = final.college_game_stats.max_by(&:final_score)
      winner&.college_id == college_season.college_id
    end
  end
end
