class RemovePositionKeyFromPositionBoards < ActiveRecord::Migration[8.0]
  def change
    remove_column :position_boards, :position_key, :string
  end
end
