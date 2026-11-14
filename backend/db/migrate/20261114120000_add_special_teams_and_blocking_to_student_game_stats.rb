# Kicking, punting, return and blocking lines from the Dynasty Rewired box scores. The game stats screens these
# come from were never captured, so every column is nil until a box score import (or backfill) fills it.
class AddSpecialTeamsAndBlockingToStudentGameStats < ActiveRecord::Migration[8.0]
  COLUMNS = %i[
    kicking_fgm kicking_fga kicking_fg_longest kicking_xpm kicking_xpa
    punting_punts punting_yards punting_longest punting_inside_20 punting_touchbacks
    kick_returns kick_return_yards kick_return_tds kick_return_longest
    punt_returns punt_return_yards punt_return_tds punt_return_longest
    blocking_pancakes blocking_sacks_allowed
  ].freeze

  def change
    COLUMNS.each { |column| add_column :student_game_stats, column, :integer }
  end
end
