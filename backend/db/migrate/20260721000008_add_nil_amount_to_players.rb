class AddNilAmountToPlayers < ActiveRecord::Migration[8.0]
  def change
    add_column :players, :nil_amount, :integer
  end
end