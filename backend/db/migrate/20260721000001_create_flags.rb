class CreateFlags < ActiveRecord::Migration[8.0]
  def change
    create_table :flags do |t|
      t.string :name, null: false
      t.string :icon, null: false
      t.string :color, null: false
      t.timestamps
    end
    add_index :flags, :name, unique: true
  end
end
