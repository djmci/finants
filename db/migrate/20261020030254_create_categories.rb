class CreateCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :categories do |t|
      t.string :name, null: false
      t.string :kind, null: false, default: "expense"
      t.references :parent, null: true, foreign_key: { to_table: :categories }
      t.string :colour
      t.boolean :active, null: false, default: true

      t.timestamps
    end
  end
end
