class AddColumnsOnAdminUsers < ActiveRecord::Migration[6.1]
  def change
    add_column :admin_users, :kabo_customer, :boolean, null: false, default: false
    add_column :admin_users, :create_scopes, :string
    add_column :admin_users, :read_scopes, :string
    add_column :admin_users, :update_scopes, :string
    add_column :admin_users, :delete_scopes, :string
  end
end
