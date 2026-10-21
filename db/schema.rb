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

ActiveRecord::Schema[8.1].define(version: 2026_10_21_215622) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accounts", force: :cascade do |t|
    t.string "name", null: false
    t.string "kind", default: "everyday", null: false
    t.string "currency", default: "AUD", null: false
    t.integer "opening_balance_cents", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.bigint "owner_id"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id"], name: "index_accounts_on_owner_id"
  end

  create_table "categories", force: :cascade do |t|
    t.string "name", null: false
    t.string "kind", default: "expense", null: false
    t.bigint "parent_id"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "exclude_from_forecast", default: false, null: false
    t.index ["parent_id"], name: "index_categories_on_parent_id"
  end

  create_table "imports", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "account_id"
    t.string "filename"
    t.string "source_format"
    t.integer "rows_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status", default: "draft", null: false
    t.json "mapping"
    t.binary "payload"
    t.index ["account_id"], name: "index_imports_on_account_id"
    t.index ["user_id"], name: "index_imports_on_user_id"
  end

  create_table "payee_rules", force: :cascade do |t|
    t.string "pattern", null: false
    t.bigint "category_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "round_amount"
    t.integer "max_amount_cents"
    t.string "direction"
    t.boolean "auto", default: true, null: false
    t.index ["category_id"], name: "index_payee_rules_on_category_id"
    t.index ["pattern", "round_amount", "max_amount_cents", "direction"], name: "index_payee_rules_on_pattern_and_conditions", unique: true
  end

  create_table "recurring_rules", force: :cascade do |t|
    t.string "payee", null: false
    t.bigint "account_id", null: false
    t.bigint "category_id"
    t.bigint "to_account_id"
    t.string "kind", default: "expense", null: false
    t.integer "amount_cents", null: false
    t.string "frequency", null: false
    t.integer "every", default: 1, null: false
    t.date "start_on", null: false
    t.date "end_on"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "include_in_hybrid", default: true, null: false
    t.bigint "scenario_id"
    t.index ["account_id"], name: "index_recurring_rules_on_account_id"
    t.index ["category_id"], name: "index_recurring_rules_on_category_id"
    t.index ["scenario_id"], name: "index_recurring_rules_on_scenario_id"
    t.index ["to_account_id"], name: "index_recurring_rules_on_to_account_id"
  end

  create_table "scenarios", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "settings", force: :cascade do |t|
    t.string "key"
    t.string "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_settings_on_key", unique: true
  end

  create_table "transactions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "category_id"
    t.bigint "import_id"
    t.bigint "user_id"
    t.date "posted_on", null: false
    t.string "payee"
    t.integer "amount_cents", null: false
    t.text "notes"
    t.string "transfer_pair_id"
    t.string "import_hash"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "recurring_rule_id"
    t.index ["account_id", "import_hash"], name: "index_transactions_on_account_id_and_import_hash", unique: true, where: "(import_hash IS NOT NULL)"
    t.index ["account_id"], name: "index_transactions_on_account_id"
    t.index ["category_id"], name: "index_transactions_on_category_id"
    t.index ["import_id"], name: "index_transactions_on_import_id"
    t.index ["posted_on"], name: "index_transactions_on_posted_on"
    t.index ["recurring_rule_id"], name: "index_transactions_on_recurring_rule_id"
    t.index ["transfer_pair_id"], name: "index_transactions_on_transfer_pair_id"
    t.index ["user_id"], name: "index_transactions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name"
    t.string "role"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "accounts", "users", column: "owner_id"
  add_foreign_key "categories", "categories", column: "parent_id"
  add_foreign_key "imports", "accounts"
  add_foreign_key "imports", "users"
  add_foreign_key "payee_rules", "categories"
  add_foreign_key "recurring_rules", "accounts"
  add_foreign_key "recurring_rules", "accounts", column: "to_account_id"
  add_foreign_key "recurring_rules", "categories"
  add_foreign_key "recurring_rules", "scenarios"
  add_foreign_key "sessions", "users"
  add_foreign_key "transactions", "accounts"
  add_foreign_key "transactions", "categories"
  add_foreign_key "transactions", "imports"
  add_foreign_key "transactions", "recurring_rules"
  add_foreign_key "transactions", "users"
end
