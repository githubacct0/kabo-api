class CreateFoodBrands < ActiveRecord::Migration[6.1]
  def change
    create_table :food_brands do |t|
      t.string :name
      t.integer :food_type

      t.timestamps default: -> { "CURRENT_TIMESTAMP" }
    end
  end
end
