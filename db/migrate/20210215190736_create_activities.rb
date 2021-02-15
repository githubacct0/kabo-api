class CreateActivities < ActiveRecord::Migration[6.1]
  def change
    create_table :activities do |t|
      t.belongs_to :user

      t.string :title, null: false
      t.string :description, null: false
      t.boolean :is_read, null: false, default: false
      t.integer :kind, null: false

      t.timestamps
    end
  end
end
