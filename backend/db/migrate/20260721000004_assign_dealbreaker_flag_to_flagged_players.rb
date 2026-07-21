class AssignDealbreakerFlagToFlaggedPlayers < ActiveRecord::Migration[8.0]
  class MigrationFlag < ActiveRecord::Base
    self.table_name = "flags"
  end

  class MigrationPlayer < ActiveRecord::Base
    self.table_name = "players"
  end

  class MigrationPlayerFlag < ActiveRecord::Base
    self.table_name = "player_flags"
  end

  def up
    dealbreaker = MigrationFlag.find_by!(name: "dealbreaker")
    MigrationPlayer.where(flagged: true).find_each do |player|
      MigrationPlayerFlag.create!(player_id: player.id, flag_id: dealbreaker.id)
    end
  end

  def down
    dealbreaker = MigrationFlag.find_by(name: "dealbreaker")
    return unless dealbreaker

    MigrationPlayerFlag.where(flag_id: dealbreaker.id).delete_all
  end
end
