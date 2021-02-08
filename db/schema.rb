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

ActiveRecord::Schema.define(version: 2021_02_08_223228) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "admin_users", force: :cascade do |t|
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
    t.boolean "kabo_customer", default: false, null: false
    t.string "create_scopes"
    t.string "read_scopes"
    t.string "update_scopes"
    t.string "delete_scopes"
    t.index ["email"], name: "index_admin_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_admin_users_on_reset_password_token", unique: true
  end

  create_table "breeds", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", precision: 6, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "updated_at", precision: 6, default: -> { "CURRENT_TIMESTAMP" }, null: false
  end

  create_table "dogs", force: :cascade do |t|
    t.bigint "user_id"
    t.string "name"
    t.integer "main_breed_id"
    t.integer "secondary_breed_id"
    t.integer "age_range"
    t.integer "gender"
    t.boolean "neutered", default: false
    t.integer "weight"
    t.integer "weight_unit"
    t.integer "body_type"
    t.integer "activity_level"
    t.boolean "dry_food"
    t.boolean "wet_food"
    t.boolean "other_food"
    t.string "dry_food_brand"
    t.string "wet_food_brand"
    t.string "other_food_brand"
    t.integer "treats"
    t.boolean "food_restriction"
    t.string "food_restriction_items"
    t.string "food_restriction_custom"
    t.string "meal_type"
    t.string "chargebee_subscription_id"
    t.string "recipe"
    t.integer "portion"
    t.string "breed"
    t.integer "chargebee_unit_price"
    t.integer "chargebee_plan_units"
    t.boolean "has_custom_plan"
    t.integer "age_in_months"
    t.string "portion_adjustment"
    t.string "kibble_type"
    t.boolean "beef_recipe"
    t.boolean "chicken_recipe"
    t.boolean "turkey_recipe"
    t.string "kibble_recipe"
    t.integer "cooked_portion"
    t.integer "kibble_portion"
    t.datetime "created_at", precision: 6, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "updated_at", precision: 6, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.boolean "lamb_recipe", default: false
    t.index ["user_id"], name: "index_dogs_on_user_id"
  end

  create_table "food_brands", force: :cascade do |t|
    t.string "name"
    t.integer "food_type"
    t.datetime "created_at", precision: 6, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "updated_at", precision: 6, default: -> { "CURRENT_TIMESTAMP" }, null: false
  end

  create_table "serviceable_postal_codes", force: :cascade do |t|
    t.string "postal_code"
    t.string "province"
    t.boolean "fsa"
    t.text "notes"
    t.string "city"
    t.integer "delivery_day"
    t.boolean "loomis"
    t.boolean "fedex"
    t.datetime "created_at", precision: 6, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "updated_at", precision: 6, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["postal_code"], name: "index_serviceable_postal_codes_on_postal_code"
  end

  create_table "temp_dogs", force: :cascade do |t|
    t.bigint "temp_user_id"
    t.string "name"
    t.integer "main_breed_id"
    t.integer "secondary_breed_id"
    t.integer "age_range"
    t.integer "gender"
    t.boolean "neutered"
    t.integer "weight"
    t.integer "weight_unit"
    t.integer "body_type"
    t.integer "activity_level"
    t.boolean "dry_food"
    t.boolean "wet_food"
    t.boolean "other_food"
    t.string "dry_food_brand"
    t.string "wet_food_brand"
    t.string "other_food_brand"
    t.integer "treats"
    t.boolean "food_restriction"
    t.string "food_restriction_items"
    t.string "food_restriction_custom"
    t.string "meal_type"
    t.string "recipe"
    t.integer "portion"
    t.string "breed"
    t.integer "age_in_months"
    t.string "kibble_type"
    t.boolean "beef_recipe"
    t.boolean "chicken_recipe"
    t.boolean "turkey_recipe"
    t.string "kibble_recipe"
    t.integer "cooked_portion"
    t.integer "kibble_portion"
    t.datetime "created_at", precision: 6, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "updated_at", precision: 6, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.boolean "lamb_recipe", default: false
    t.index ["temp_user_id"], name: "index_temp_dogs_on_temp_user_id"
  end

  create_table "temp_users", force: :cascade do |t|
    t.string "first_name"
    t.string "email"
    t.string "postal_code"
    t.integer "plan_interval"
    t.datetime "created_at", precision: 6, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "updated_at", precision: 6, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "checkout_token"
    t.string "chargebee_plan_interval"
  end

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
    t.boolean "billing_override", default: false, null: false
    t.string "referral_code"
    t.string "klaviyo_id"
    t.datetime "last_active_at"
    t.boolean "skipped_first_box", default: false
    t.string "subscription_phase_status"
    t.integer "trial_length", default: 2
    t.datetime "first_checkout_at"
    t.integer "qa_jump_by_days", default: 0, null: false
    t.boolean "one_time_purchase", default: false, null: false
    t.string "one_time_purchase_dog_names"
    t.string "one_time_purchase_sku"
    t.integer "one_time_purchase_quantity", default: 0, null: false
    t.string "one_time_purchase_email"
    t.string "shipping_postal_code"
    t.string "shipping_province"
    t.boolean "migrated_mealplan_v2", default: false
    t.index ["checkout_token"], name: "index_users_on_checkout_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

end
