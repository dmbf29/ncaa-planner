class SeedFlags < ActiveRecord::Migration[8.0]
  class MigrationFlag < ActiveRecord::Base
    self.table_name = "flags"
  end

  FLAGS = [
    { name: "replace", icon: "fa-solid fa-arrows-rotate", color: "#2563EB" },
    { name: "dealbreaker", icon: "fa-solid fa-heart-crack", color: "#991B1B" },
    { name: "position", icon: "fa-solid fa-arrows-up-down-left-right", color: "#7C3AED" },
    { name: "redshirt", icon: "fa-solid fa-shirt", color: "#D97706" },
    { name: "draft", icon: "fa-solid fa-door-open", color: "#059669" },
    { name: "watch", icon: "fa-solid fa-eye", color: "#0891B2" },
  ].freeze

  def up
    FLAGS.each { |attrs| MigrationFlag.create!(attrs) }
  end

  def down
    MigrationFlag.where(name: FLAGS.map { |f| f[:name] }).delete_all
  end
end
