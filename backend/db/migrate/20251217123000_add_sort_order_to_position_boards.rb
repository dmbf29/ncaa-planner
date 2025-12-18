class AddSortOrderToPositionBoards < ActiveRecord::Migration[8.0]
  def change
    add_column :position_boards, :sort_order, :integer, null: false, default: 0
    add_index :position_boards, [:squad_id, :sort_order]
  end
end
