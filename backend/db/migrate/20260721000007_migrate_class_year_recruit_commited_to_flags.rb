class MigrateClassYearRecruitCommitedToFlags < ActiveRecord::Migration[8.0]
  class MigrationFlag < ActiveRecord::Base
    self.table_name = "flags"
  end

  class MigrationPlayer < ActiveRecord::Base
    self.table_name = "players"
  end

  class MigrationPlayerFlag < ActiveRecord::Base
    self.table_name = "player_flags"
  end

  MAPPING = {
    "Rec" => "recruit",
    "✍️" => "commited",
  }.freeze

  def up
    MAPPING.each do |class_year, flag_name|
      flag = MigrationFlag.find_by!(name: flag_name)
      MigrationPlayer.where(class_year: class_year).find_each do |player|
        MigrationPlayerFlag.find_or_create_by!(player_id: player.id, flag_id: flag.id)
        player.update!(class_year: nil)
      end
    end
  end

  def down
    # Data migration; class_year values and flag assignments are not restored.
  end
end
