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

ActiveRecord::Schema[8.1].define(version: 2026_03_02_100033) do
  create_table "groups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "hosts", force: :cascade do |t|
    t.string "address"
    t.datetime "created_at", null: false
    t.integer "group_id", null: false
    t.integer "interval", default: 60, null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["group_id"], name: "index_hosts_on_group_id"
  end

  create_table "pings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "host_id", null: false
    t.float "latency"
    t.float "max_latency"
    t.float "min_latency"
    t.integer "packet_loss"
    t.datetime "recorded_at"
    t.datetime "updated_at", null: false
    t.index ["host_id", "recorded_at"], name: "index_pings_on_host_id_and_recorded_at"
    t.index ["host_id"], name: "index_pings_on_host_id"
    t.index ["recorded_at"], name: "index_pings_on_recorded_at"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "hosts", "groups"
  add_foreign_key "pings", "hosts"
  add_foreign_key "sessions", "users"
end
