class CreateBreeds < ActiveRecord::Migration[6.1]
  def change
    create_table :breeds do |t|
      t.string :name

      t.timestamps default: -> { "CURRENT_TIMESTAMP" }
    end
  end
end
