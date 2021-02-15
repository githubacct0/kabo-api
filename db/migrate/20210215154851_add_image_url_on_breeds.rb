class AddImageUrlOnBreeds < ActiveRecord::Migration[6.1]
  def change
  	add_column :breeds, :image_url, :string
  end
end
