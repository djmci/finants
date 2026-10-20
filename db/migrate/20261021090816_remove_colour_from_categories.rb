class RemoveColourFromCategories < ActiveRecord::Migration[8.1]
  def change
    remove_column :categories, :colour, :string
  end
end
