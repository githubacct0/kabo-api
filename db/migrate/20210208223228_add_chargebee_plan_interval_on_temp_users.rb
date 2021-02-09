class AddChargebeePlanIntervalOnTempUsers < ActiveRecord::Migration[6.1]
  def change
  	add_column :temp_users, :chargebee_plan_interval, :string
  end
end
