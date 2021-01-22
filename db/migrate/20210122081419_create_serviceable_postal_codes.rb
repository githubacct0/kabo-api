class CreateServiceablePostalCodes < ActiveRecord::Migration[6.1]
  def change
    create_table :serviceable_postal_codes do |t|
      t.string :postal_code
      t.string :province
      t.boolean :fsa
      t.text :notes
      t.string :city
      t.integer :delivery_day
      t.boolean :loomis
      t.boolean :fedex

      t.timestamps default: -> { "CURRENT_TIMESTAMP" }
    end

    add_index :serviceable_postal_codes, :postal_code
  end
end
