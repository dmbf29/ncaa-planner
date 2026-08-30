class CreateSeasonAwards < ActiveRecord::Migration[8.0]
  def change
    create_table :season_awards do |t|
      t.references :season, null: false, foreign_key: true
      t.references :award, null: false, foreign_key: true
      # Exactly one of these is set, enforced by the check constraint below.
      # student_season is season-scoped; coach is dynasty-scoped (a CPU
      # coach can win COTY in more than one season without a per-season row).
      t.references :student_season, foreign_key: true
      t.references :coach, foreign_key: true
      t.string :stat_line
      t.timestamps
    end

    add_index :season_awards, %i[season_id award_id], unique: true
    add_check_constraint :season_awards,
                         "(student_season_id IS NOT NULL) <> (coach_id IS NOT NULL)",
                         name: "season_awards_exactly_one_recipient"
  end
end
