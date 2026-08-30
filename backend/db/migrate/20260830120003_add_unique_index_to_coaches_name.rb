class AddUniqueIndexToCoachesName < ActiveRecord::Migration[8.0]
  # A coach is identified within a dynasty by name. Award commits can
  # create CPU coaches on the fly (nobody sets them up otherwise), so guard
  # against "Kirby Smart" being entered twice with different casing and
  # forking into two records.
  def change
    add_index :coaches, "dynasty_id, lower(name)", unique: true, name: "index_coaches_on_dynasty_id_and_lower_name"
  end
end
