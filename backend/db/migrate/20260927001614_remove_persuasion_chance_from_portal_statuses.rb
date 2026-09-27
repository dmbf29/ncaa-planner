class RemovePersuasionChanceFromPortalStatuses < ActiveRecord::Migration[8.0]
  def change
    remove_column :portal_statuses, :persuasion_chance, :string
  end
end
