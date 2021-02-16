class CreateUsersPromotions < ActiveRecord::Migration[6.1]
  def change
    create_table :users_promotions do |t|
      t.belongs_to :user
      t.belongs_to :promotion

      t.timestamps default: -> { "CURRENT_TIMESTAMP" }
    end
  end
end
