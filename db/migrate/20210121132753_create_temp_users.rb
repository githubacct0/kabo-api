class CreateTempUsers < ActiveRecord::Migration[6.1]
  def change
    create_table :temp_users do |t|
      t.string :first_name
      t.string :email
      t.string :postal_code
      t.integer :plan_interval

      t.timestamps default: -> { "CURRENT_TIMESTAMP" }
    end
  end
end
