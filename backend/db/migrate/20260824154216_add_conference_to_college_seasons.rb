class AddConferenceToCollegeSeasons < ActiveRecord::Migration[8.0]
  def up
    add_column :college_seasons, :conference, :string

    execute <<~SQL
      UPDATE college_seasons
      SET conference = colleges.conference
      FROM colleges
      WHERE colleges.id = college_seasons.college_id
    SQL
  end

  def down
    remove_column :college_seasons, :conference
  end
end
