class MigrateSeasonHeismanToSeasonAwards < ActiveRecord::Migration[8.0]
  class MigrationAward < ActiveRecord::Base
    self.table_name = "awards"
  end

  class MigrationSeasonAward < ActiveRecord::Base
    self.table_name = "season_awards"
  end

  class MigrationSeason < ActiveRecord::Base
    self.table_name = "seasons"
  end

  # Moves the single Heisman winner stored on seasons.heisman_id into the
  # generic season_awards table, then drops the column. SeedAwards runs
  # first, but guard anyway so this is safe on any DB state.
  def up
    heisman = MigrationAward.find_or_create_by!(name: "Heisman Trophy") do |award|
      award.description = "College football's most prestigious award, given to the nation's most outstanding player."
      award.recipient_type = "player"
      award.sort_order = 0
    end

    MigrationSeason.where.not(heisman_id: nil).find_each do |season|
      MigrationSeasonAward.find_or_create_by!(season_id: season.id, award_id: heisman.id) do |season_award|
        season_award.student_season_id = season.heisman_id
      end
    end

    remove_reference :seasons, :heisman
  end

  def down
    add_reference :seasons, :heisman, foreign_key: { to_table: :student_seasons }

    heisman = MigrationAward.find_by(name: "Heisman Trophy")
    return unless heisman

    MigrationSeasonAward.where(award_id: heisman.id).where.not(student_season_id: nil).find_each do |season_award|
      MigrationSeason.where(id: season_award.season_id).update_all(heisman_id: season_award.student_season_id)
    end
  end
end
