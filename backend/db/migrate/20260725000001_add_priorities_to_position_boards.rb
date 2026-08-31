class AddPrioritiesToPositionBoards < ActiveRecord::Migration[8.0]
  def change
    add_column :position_boards, :priorities, :integer, null: false, default: 0
  end
end
