class AddCheckoutTokenOnTempUsers < ActiveRecord::Migration[6.1]
  def change
  	add_column :temp_users, :checkout_token, :string
  end
end
