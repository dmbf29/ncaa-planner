class AddHeismanToSeasons < ActiveRecord::Migration[8.0]
  def change
    add_reference :seasons, :heisman, foreign_key: { to_table: :student_seasons }
  end
end
