class AddTransferAndClassYearToSignedRecruits < ActiveRecord::Migration[8.0]
  def change
    add_column :signed_recruits, :transfer, :boolean, default: false, null: false
    add_column :signed_recruits, :class_year, :string
  end
end
