class AddAlternateNameToColleges < ActiveRecord::Migration[8.0]
  def change
    add_column :colleges, :alternate_name, :string
  end
end
