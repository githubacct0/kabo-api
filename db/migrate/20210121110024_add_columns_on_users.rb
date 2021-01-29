class AddColumnsOnUsers < ActiveRecord::Migration[6.1]
  def change
    add_column :users, :chargebee_plan_interval, :string
    add_column :users, :verified, :boolean, default: false
    add_column :users, :chargebee_customer_id, :string
    add_column :users, :checkout_token, :string
    add_column :users, :first_name, :string
    add_column :users, :postal_code, :string
    add_column :users, :no_meals, :boolean, default: false
    add_column :users, :postal_code_override, :boolean, default: false
    add_column :users, :admin, :boolean, default: false
    add_column :users, :trial, :boolean, default: false
    add_column :users, :trial_dog_name, :string
    add_column :users, :billing_override, :boolean
    add_column :users, :referral_code, :string
    add_column :users, :klaviyo_id, :string
    add_column :users, :last_active_at, :datetime
    add_column :users, :skipped_first_box, :boolean, default: false
    add_column :users, :subscription_phase_status, :string
    add_column :users, :trial_length, :integer, default: 2
    add_column :users, :first_checkout_at, :datetime
    add_column :users, :qa_jump_by_days, :integer
    add_column :users, :one_time_purchase, :boolean
    add_column :users, :one_time_purchase_dog_names, :string
    add_column :users, :one_time_purchase_sku, :string
    add_column :users, :one_time_purchase_quantity, :integer
    add_column :users, :one_time_purchase_email, :string
    add_column :users, :shipping_postal_code, :string
    add_column :users, :shipping_province, :string
    add_column :users, :migrated_mealplan_v2, :boolean, default: false

    add_index :users, :checkout_token, unique: true
  end
end
