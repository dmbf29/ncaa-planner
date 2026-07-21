class SeedRecruitAndCommitedFlags < ActiveRecord::Migration[8.0]
  class MigrationFlag < ActiveRecord::Base
    self.table_name = "flags"
  end

  FLAGS = [
    { name: "recruit", icon: "fa-solid fa-magnifying-glass", color: "#DB2777" },
    { name: "commited", icon: "fa-solid fa-file-signature", color: "#65A30D" },
  ].freeze

  def up
    FLAGS.each { |attrs| MigrationFlag.create!(attrs) }
  end

  def down
    MigrationFlag.where(name: FLAGS.map { |f| f[:name] }).delete_all
  end
end
