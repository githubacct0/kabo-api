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

ActiveRecord::Schema.define(version: 2021_01_21_110024) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "chargebee_plan_interval"
    t.boolean "verified", default: false
    t.string "chargebee_customer_id"
    t.string "checkout_token"
    t.string "first_name"
    t.string "postal_code"
    t.boolean "no_meals", default: false
    t.boolean "postal_code_override", default: false
    t.boolean "admin", default: false
    t.boolean "trial", default: false
    t.string "trial_dog_name"
    t.boolean "billing_override"
    t.string "referral_code"
    t.string "klaviyo_id"
    t.datetime "last_active_at"
    t.boolean "skipped_first_box", default: false
    t.string "subscription_phase_status"
    t.integer "trial_length", default: 2
    t.datetime "first_checkout_at"
    t.integer "qa_jump_by_days"
    t.boolean "one_time_purchase"
    t.string "one_time_purchase_dog_names"
    t.string "one_time_purchase_sku"
    t.integer "one_time_purchase_quantity"
    t.string "one_time_purchase_email"
    t.string "shipping_postal_code"
    t.string "shipping_province"
    t.boolean "migrated_mealplan_v2", default: false
    t.index ["checkout_token"], name: "index_users_on_checkout_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

end
