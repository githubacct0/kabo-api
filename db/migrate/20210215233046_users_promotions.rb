class UsersPromotions < ActiveRecord::Migration[6.1]
  def change
    t.belongs_to :user
    t.belongs_to :promotion
  end
end
