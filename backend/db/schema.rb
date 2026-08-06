# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_08_05_233038) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "all_americans", force: :cascade do |t|
    t.bigint "student_season_id", null: false
    t.boolean "national", default: false, null: false
    t.string "conference"
    t.integer "tier", null: false
    t.boolean "preseason", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["student_season_id", "national", "conference", "preseason"], name: "index_all_americans_on_student_season_and_category", unique: true
    t.index ["student_season_id"], name: "index_all_americans_on_student_season_id"
  end

  create_table "coaches", force: :cascade do |t|
    t.string "name", null: false
    t.bigint "dynasty_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["dynasty_id"], name: "index_coaches_on_dynasty_id"
  end

  create_table "college_game_stats", force: :cascade do |t|
    t.bigint "game_id", null: false
    t.bigint "college_id", null: false
    t.integer "first_downs"
    t.integer "total_offense"
    t.integer "total_plays"
    t.float "yards_per_play"
    t.integer "rushes"
    t.integer "rushing_yards"
    t.integer "rushing_tds"
    t.float "yards_per_rush"
    t.integer "passing_completions"
    t.integer "passing_attempts"
    t.integer "passing_yards"
    t.integer "passing_tds"
    t.float "yards_per_pass"
    t.integer "third_down_conversions"
    t.integer "third_down_attempts"
    t.integer "fourth_down_conversions"
    t.integer "fourth_down_attempts"
    t.integer "two_point_attempts"
    t.integer "two_point_conversions"
    t.integer "red_zone_tds"
    t.integer "red_zone_field_goals"
    t.float "red_zone_success_percentage"
    t.integer "turnovers"
    t.integer "fumbles_lost"
    t.integer "interceptions_thrown"
    t.integer "punt_return_yards"
    t.integer "kick_return_yards"
    t.integer "total_yards"
    t.integer "punts"
    t.integer "penalties"
    t.integer "penalty_yards"
    t.integer "time_of_possession"
    t.integer "points_in_quarter_1"
    t.integer "points_in_quarter_2"
    t.integer "points_in_quarter_3"
    t.integer "points_in_quarter_4"
    t.integer "final_score"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["college_id"], name: "index_college_game_stats_on_college_id"
    t.index ["game_id", "college_id"], name: "index_college_game_stats_on_game_and_college", unique: true
    t.index ["game_id"], name: "index_college_game_stats_on_game_id"
  end

  create_table "college_seasons", force: :cascade do |t|
    t.integer "offense"
    t.integer "defense"
    t.float "prestige"
    t.integer "recruiting_rank"
    t.bigint "college_id", null: false
    t.bigint "coach_id"
    t.bigint "season_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "overall"
    t.integer "wins"
    t.integer "losses"
    t.integer "nil_spend"
    t.jsonb "nil_spend_by_position", default: {}, null: false
    t.integer "conference_wins"
    t.integer "conference_losses"
    t.integer "conference_points_for"
    t.integer "conference_points_against"
    t.integer "points_for"
    t.integer "points_against"
    t.integer "home_wins"
    t.integer "home_losses"
    t.index ["coach_id"], name: "index_college_seasons_on_coach_id"
    t.index ["college_id"], name: "index_college_seasons_on_college_id"
    t.index ["season_id"], name: "index_college_seasons_on_season_id"
  end

  create_table "college_week_rankings", force: :cascade do |t|
    t.bigint "college_id", null: false
    t.bigint "week_id", null: false
    t.integer "ranking", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["college_id"], name: "index_college_week_rankings_on_college_id"
    t.index ["week_id", "college_id"], name: "index_college_week_rankings_on_week_and_college", unique: true
    t.index ["week_id"], name: "index_college_week_rankings_on_week_id"
  end

  create_table "colleges", force: :cascade do |t|
    t.string "name"
    t.integer "api_id"
    t.float "prestige"
    t.integer "overall"
    t.integer "offense"
    t.integer "defense"
    t.string "conference"
    t.integer "nil_total"
    t.integer "capacity"
    t.integer "pipeline_ranking"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "dynasties", force: :cascade do |t|
    t.string "name", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_dynasties_on_user_id"
  end

  create_table "flags", force: :cascade do |t|
    t.string "name", null: false
    t.string "icon", null: false
    t.string "color", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_flags_on_name", unique: true
  end

  create_table "games", force: :cascade do |t|
    t.bigint "week_id", null: false
    t.datetime "time"
    t.bigint "home_college_id", null: false
    t.bigint "away_college_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "narrative_summary"
    t.bigint "offensive_player_of_game_id"
    t.string "offensive_player_stat_line"
    t.bigint "defensive_player_of_game_id"
    t.string "defensive_player_stat_line"
    t.index ["away_college_id"], name: "index_games_on_away_college_id"
    t.index ["defensive_player_of_game_id"], name: "index_games_on_defensive_player_of_game_id"
    t.index ["home_college_id"], name: "index_games_on_home_college_id"
    t.index ["offensive_player_of_game_id"], name: "index_games_on_offensive_player_of_game_id"
    t.index ["week_id"], name: "index_games_on_week_id"
    t.check_constraint "home_college_id <> away_college_id", name: "games_home_away_college_different"
  end

  create_table "heisman_candidates", force: :cascade do |t|
    t.bigint "week_id", null: false
    t.bigint "student_season_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["student_season_id"], name: "index_heisman_candidates_on_student_season_id"
    t.index ["week_id", "student_season_id"], name: "index_heisman_candidates_on_week_and_student_season", unique: true
    t.index ["week_id"], name: "index_heisman_candidates_on_week_id"
  end

  create_table "player_flags", force: :cascade do |t|
    t.bigint "player_id", null: false
    t.bigint "flag_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["flag_id"], name: "index_player_flags_on_flag_id"
    t.index ["player_id", "flag_id"], name: "index_player_flags_on_player_id_and_flag_id", unique: true
    t.index ["player_id"], name: "index_player_flags_on_player_id"
  end

  create_table "players", force: :cascade do |t|
    t.string "name", null: false
    t.string "class_year"
    t.string "dev_trait"
    t.string "archetype"
    t.integer "status", default: 0, null: false
    t.integer "star_rating"
    t.string "eval_status"
    t.integer "overall"
    t.jsonb "attribute_values", default: {}, null: false
    t.jsonb "abilities", default: [], null: false
    t.jsonb "tags", default: [], null: false
    t.text "notes"
    t.boolean "pursued", default: false, null: false
    t.boolean "signed", default: false, null: false
    t.boolean "position_change_needed", default: false, null: false
    t.bigint "team_id", null: false
    t.bigint "squad_id"
    t.bigint "position_board_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "recruit_status", default: 0, null: false
    t.integer "nil_amount"
    t.index ["position_board_id", "status"], name: "index_players_on_position_board_id_and_status"
    t.index ["position_board_id"], name: "index_players_on_position_board_id"
    t.index ["recruit_status"], name: "index_players_on_recruit_status"
    t.index ["squad_id"], name: "index_players_on_squad_id"
    t.index ["team_id", "status"], name: "index_players_on_team_id_and_status"
    t.index ["team_id"], name: "index_players_on_team_id"
  end

  create_table "position_boards", force: :cascade do |t|
    t.string "name", null: false
    t.integer "slots_count", default: 0, null: false
    t.jsonb "highlighted_attributes", default: [], null: false
    t.jsonb "target_archetypes", default: [], null: false
    t.text "notes"
    t.bigint "team_id", null: false
    t.bigint "squad_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "sort_order", default: 0, null: false
    t.integer "priorities", default: 0, null: false
    t.index ["squad_id", "sort_order"], name: "index_position_boards_on_squad_id_and_sort_order"
    t.index ["squad_id"], name: "index_position_boards_on_squad_id"
    t.index ["team_id"], name: "index_position_boards_on_team_id"
  end

  create_table "roster_slots", force: :cascade do |t|
    t.bigint "position_board_id", null: false
    t.bigint "player_id", null: false
    t.integer "slot_number", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["player_id"], name: "index_roster_slots_on_player_id"
    t.index ["position_board_id", "player_id"], name: "index_roster_slots_on_position_board_id_and_player_id", unique: true
    t.index ["position_board_id", "slot_number"], name: "index_roster_slots_on_position_board_id_and_slot_number", unique: true
    t.index ["position_board_id"], name: "index_roster_slots_on_position_board_id"
  end

  create_table "seasons", force: :cascade do |t|
    t.integer "year", null: false
    t.bigint "dynasty_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "heisman_id"
    t.index ["dynasty_id"], name: "index_seasons_on_dynasty_id"
    t.index ["heisman_id"], name: "index_seasons_on_heisman_id"
  end

  create_table "squads", force: :cascade do |t|
    t.string "name", null: false
    t.bigint "team_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["team_id", "name"], name: "index_squads_on_team_id_and_name", unique: true
    t.index ["team_id"], name: "index_squads_on_team_id"
  end

  create_table "student_game_stats", force: :cascade do |t|
    t.bigint "game_id", null: false
    t.bigint "student_season_id", null: false
    t.float "passing_rating"
    t.integer "passing_yards"
    t.integer "passing_tds"
    t.integer "passing_interceptions"
    t.integer "passing_longest"
    t.integer "passing_sacks_taken"
    t.integer "passing_completions"
    t.integer "passing_attempts"
    t.float "passing_avg"
    t.integer "rushing_carries"
    t.integer "rushing_yards"
    t.float "rushing_avg"
    t.integer "rushing_tds"
    t.integer "rushing_fumbles"
    t.integer "rushing_yac"
    t.integer "rushing_longest"
    t.integer "receiving_receptions"
    t.integer "receiving_yards"
    t.float "receiving_avg"
    t.integer "receiving_tds"
    t.integer "receiving_rac"
    t.integer "receiving_longest"
    t.integer "receiving_drop"
    t.integer "defense_solo_tackles"
    t.integer "defense_assist_tackles"
    t.integer "defense_tackles"
    t.integer "defense_tfl"
    t.float "defense_sacks"
    t.integer "defense_interceptions"
    t.integer "defense_interceptions_longest"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["game_id", "student_season_id"], name: "index_student_game_stats_on_game_and_student_season", unique: true
    t.index ["game_id"], name: "index_student_game_stats_on_game_id"
    t.index ["student_season_id"], name: "index_student_game_stats_on_student_season_id"
  end

  create_table "student_seasons", force: :cascade do |t|
    t.string "class_year", null: false
    t.string "position", null: false
    t.integer "overall"
    t.integer "nil_amount"
    t.string "dev_trait"
    t.integer "speed"
    t.bigint "student_id", null: false
    t.bigint "college_season_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["college_season_id"], name: "index_student_seasons_on_college_season_id"
    t.index ["student_id"], name: "index_student_seasons_on_student_id"
  end

  create_table "students", force: :cascade do |t|
    t.string "first_name"
    t.string "last_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "teams", force: :cascade do |t|
    t.string "name", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "college_id"
    t.index ["college_id"], name: "index_teams_on_college_id"
    t.index ["user_id", "name"], name: "index_teams_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_teams_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "name"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "jti", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["jti"], name: "index_users_on_jti", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "weeks", force: :cascade do |t|
    t.integer "number", null: false
    t.string "name"
    t.bigint "season_id", null: false
    t.boolean "conference_championship", default: false, null: false
    t.boolean "post_season", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["season_id"], name: "index_weeks_on_season_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "all_americans", "student_seasons"
  add_foreign_key "coaches", "dynasties"
  add_foreign_key "college_game_stats", "colleges"
  add_foreign_key "college_game_stats", "games"
  add_foreign_key "college_seasons", "coaches"
  add_foreign_key "college_seasons", "colleges"
  add_foreign_key "college_seasons", "seasons"
  add_foreign_key "college_week_rankings", "colleges"
  add_foreign_key "college_week_rankings", "weeks"
  add_foreign_key "dynasties", "users"
  add_foreign_key "games", "colleges", column: "away_college_id"
  add_foreign_key "games", "colleges", column: "home_college_id"
  add_foreign_key "games", "student_seasons", column: "defensive_player_of_game_id"
  add_foreign_key "games", "student_seasons", column: "offensive_player_of_game_id"
  add_foreign_key "games", "weeks"
  add_foreign_key "heisman_candidates", "student_seasons"
  add_foreign_key "heisman_candidates", "weeks"
  add_foreign_key "player_flags", "flags"
  add_foreign_key "player_flags", "players"
  add_foreign_key "players", "position_boards"
  add_foreign_key "players", "squads"
  add_foreign_key "players", "teams"
  add_foreign_key "position_boards", "squads"
  add_foreign_key "position_boards", "teams"
  add_foreign_key "roster_slots", "players"
  add_foreign_key "roster_slots", "position_boards"
  add_foreign_key "seasons", "dynasties"
  add_foreign_key "seasons", "student_seasons", column: "heisman_id"
  add_foreign_key "squads", "teams"
  add_foreign_key "student_game_stats", "games"
  add_foreign_key "student_game_stats", "student_seasons"
  add_foreign_key "student_seasons", "college_seasons"
  add_foreign_key "student_seasons", "students"
  add_foreign_key "teams", "colleges"
  add_foreign_key "teams", "users"
  add_foreign_key "weeks", "seasons"
end
