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

ActiveRecord::Schema[8.0].define(version: 2025_12_20_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "needs", force: :cascade do |t|
    t.bigint "position_board_id", null: false
    t.bigint "replacement_player_id"
    t.bigint "departing_player_id"
    t.integer "slot_number"
    t.boolean "resolved", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["departing_player_id"], name: "index_needs_on_departing_player_id"
    t.index ["position_board_id", "slot_number"], name: "index_needs_on_position_board_id_and_slot_number", unique: true, where: "(slot_number IS NOT NULL)"
    t.index ["position_board_id"], name: "index_needs_on_position_board_id"
    t.index ["replacement_player_id"], name: "index_needs_on_replacement_player_id"
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
    t.index ["position_board_id", "status"], name: "index_players_on_position_board_id_and_status"
    t.index ["position_board_id"], name: "index_players_on_position_board_id"
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

  create_table "squads", force: :cascade do |t|
    t.string "name", null: false
    t.bigint "team_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["team_id", "name"], name: "index_squads_on_team_id_and_name", unique: true
    t.index ["team_id"], name: "index_squads_on_team_id"
  end

  create_table "teams", force: :cascade do |t|
    t.string "name", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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

  add_foreign_key "needs", "players", column: "departing_player_id"
  add_foreign_key "needs", "players", column: "replacement_player_id"
  add_foreign_key "needs", "position_boards"
  add_foreign_key "players", "position_boards"
  add_foreign_key "players", "squads"
  add_foreign_key "players", "teams"
  add_foreign_key "position_boards", "squads"
  add_foreign_key "position_boards", "teams"
  add_foreign_key "roster_slots", "players"
  add_foreign_key "roster_slots", "position_boards"
  add_foreign_key "squads", "teams"
  add_foreign_key "teams", "users"
end
