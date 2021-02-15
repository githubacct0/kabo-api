class CreatePromotions < ActiveRecord::Migration[6.1]
  def change
    create_table :promotions do |t|
      t.string :title, null: false
      t.string :description, null: false
      t.boolean :is_read, null: false, default: false
      t.integer :action, null: false

      t.timestamps default: -> { "CURRENT_TIMESTAMP" }
    end
  end
end
