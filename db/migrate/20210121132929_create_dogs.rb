class CreateDogs < ActiveRecord::Migration[6.1]
  def change
    create_table :dogs do |t|
      t.belongs_to :user

      t.string :name
      t.integer :main_breed_id
      t.integer :secondary_breed_id
      t.integer :age_range
      t.integer :gender
      t.boolean :neutered, default: false
      t.integer :weight
      t.integer :weight_unit
      t.integer :body_type
      t.integer :activity_level
      t.boolean :dry_food
      t.boolean :wet_food
      t.boolean :other_food
      t.string :dry_food_brand
      t.string :wet_food_brand
      t.string :other_food_brand
      t.integer :treats
      t.boolean :food_restriction
      t.string :food_restriction_items
      t.string :food_restriction_custom
      t.string :meal_type
      t.string :chargebee_subscription_id
      t.string :recipe
      t.integer :portion
      t.string :breed
      t.integer :chargebee_unit_price
      t.integer :chargebee_plan_units
      t.boolean :has_custom_plan
      t.integer :age_in_months
      t.string :portion_adjustment
      t.string :kibble_type
      t.boolean :beef_recipe
      t.boolean :chicken_recipe
      t.boolean :turkey_recipe
      t.string :kibble_recipe
      t.integer :cooked_portion
      t.integer :kibble_portion

      t.timestamps default: -> { "CURRENT_TIMESTAMP" }
    end
  end
end
