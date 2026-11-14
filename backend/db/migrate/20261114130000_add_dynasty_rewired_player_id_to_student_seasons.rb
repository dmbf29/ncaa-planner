# Dynasty Rewired's id for a player (the `playerId` its roster and transfer portal data use), saved per season by
# the roster import so portal entries can be tied to a player without matching names.
class AddDynastyRewiredPlayerIdToStudentSeasons < ActiveRecord::Migration[8.0]
  def change
    add_column :student_seasons, :dynasty_rewired_player_id, :string
    add_index :student_seasons, :dynasty_rewired_player_id
  end
end
