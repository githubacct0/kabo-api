class AddPortionAdjustmentOnTempDogs < ActiveRecord::Migration[6.1]
  def change
  	add_column :temp_dogs, :portion_adjustment, :string
  end
end
