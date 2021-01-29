class AddLambRecipeOnDogs < ActiveRecord::Migration[6.1]
  def change
    add_column :dogs, :lamb_recipe, :boolean, default: false
  end
end
