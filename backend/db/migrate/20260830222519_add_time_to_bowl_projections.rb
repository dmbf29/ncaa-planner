class AddTimeToBowlProjections < ActiveRecord::Migration[8.0]
  def change
    add_column :bowl_projections, :time, :datetime
  end
end
