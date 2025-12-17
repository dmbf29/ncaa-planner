class RemoveDescriptionFromSquads < ActiveRecord::Migration[8.0]
  def change
    remove_column :squads, :description, :string
  end
end
