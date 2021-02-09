class AddLambRecipeOnTempDogs < ActiveRecord::Migration[6.1]
  def change
  	add_column :temp_dogs, :lamb_recipe, :boolean, default: false
  end
end
