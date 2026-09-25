module GameStats
  # Manual correction of a game's matchup/bowl details — e.g. a schedule
  # upload that matched "Arizona" when it meant "Arizona State". Stats are
  # keyed by college, so swapping a team on a game that already has stats
  # would otherwise leave them attached to a college that isn't playing:
  #
  # - The replaced college's CollegeGameStat row moves to its replacement.
  #   Team-level numbers (score, yards, ...) describe that side of the
  #   game no matter which college was mislabeled on it.
  # - The replaced college's player stats, injuries and player-of-the-game
  #   picks are removed instead. Those rows point at the wrong team's
  #   roster, so re-upload that side's screenshots (or re-enter by hand).
  #
  # Flipping home/away between the same two teams touches no stats.
  class UpdateGameService
    def initialize(game)
      @game = game
    end

    def call(attributes)
      old_colleges = [ @game.home_college, @game.away_college ]

      ActiveRecord::Base.transaction do
        @game.assign_attributes(attributes)
        @game.save!
        new_colleges = [ @game.home_college, @game.away_college ]

        replaced = old_colleges - new_colleges
        replacements = new_colleges - old_colleges
        replaced.zip(replacements).each { |old_college, new_college| move_team_stats(old_college, new_college) }
      end
      @game
    end

    private

    def move_team_stats(old_college, new_college)
      @game.college_game_stats.where(college: old_college).update_all(college_id: new_college.id)

      old_roster = StudentSeason.joins(:college_season).where(college_seasons: { college_id: old_college.id }).select(:id)
      @game.student_game_stats.where(student_season_id: old_roster).destroy_all
      @game.injuries.where(student_season_id: old_roster).destroy_all
      clear_player_of_game(old_college)
    end

    def clear_player_of_game(old_college)
      changes = {}
      if @game.offensive_player_of_game&.college_season&.college_id == old_college.id
        changes.merge!(offensive_player_of_game_id: nil, offensive_player_stat_line: nil)
      end
      if @game.defensive_player_of_game&.college_season&.college_id == old_college.id
        changes.merge!(defensive_player_of_game_id: nil, defensive_player_stat_line: nil)
      end
      @game.update!(changes) if changes.any?
    end
  end
end
