class CreatePlayersOfTheWeek < ActiveRecord::Migration[8.0]
  def change
    create_table :players_of_the_week do |t|
      t.references :week, null: false, foreign_key: true
      t.references :student_season, null: false, foreign_key: true
      t.string :side, null: false
      t.boolean :national, null: false, default: false
      t.string :conference
      t.string :stat_line

      t.timestamps
    end

    add_index :players_of_the_week, %i[week_id national conference side],
              unique: true, name: "index_players_of_the_week_on_slot"
  end
end
