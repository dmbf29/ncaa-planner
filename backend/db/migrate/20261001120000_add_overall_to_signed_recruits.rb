class AddOverallToSignedRecruits < ActiveRecord::Migration[8.0]
  def change
    add_column :signed_recruits, :overall, :integer
  end
end
