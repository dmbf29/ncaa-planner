class AddInfoToCoaches < ActiveRecord::Migration[8.0]
  def change
    add_column :coaches, :offensive_scheme, :string
    add_column :coaches, :defensive_scheme, :string
  end
end
