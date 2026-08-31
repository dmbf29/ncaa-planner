class AddAbbrevToColleges < ActiveRecord::Migration[8.0]
  def change
    add_column :colleges, :abbrev, :string
  end
end
