class AddRatingsToStudentSeasons < ActiveRecord::Migration[8.0]
  # Position-specific attribute ratings (Throw Power for a QB, Run Block for a lineman, ...) keyed by snake_cased name.
  # The six ratings every position shares keep their own columns.
  def change
    add_column :student_seasons, :ratings, :jsonb, null: false, default: {}
  end
end
