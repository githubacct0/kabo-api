class ChangeColumnsOnUsers < ActiveRecord::Migration[6.1]
  def change
    change_column :users, :billing_override, :boolean, null: false, default: false
    change_column :users, :qa_jump_by_days, :integer, null: false, default: 0
    change_column :users, :one_time_purchase, :boolean, null: false, default: false
    change_column :users, :one_time_purchase_quantity, :integer, null: false, default: 0
  end
end
