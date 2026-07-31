class CreateColleges < ActiveRecord::Migration[8.0]
  def change
    create_table :colleges do |t|
      t.string :name
      t.integer :api_id
      t.float :prestige
      t.integer :overall
      t.integer :offense
      t.integer :defense
      t.string :conference
      t.integer :nil_total
      t.integer :capacity
      t.integer :pipeline_ranking

      t.timestamps
    end
  end
end
