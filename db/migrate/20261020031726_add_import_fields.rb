class AddImportFields < ActiveRecord::Migration[8.1]
  def change
    add_column :imports, :status, :string, null: false, default: "draft"
    add_column :imports, :payload, :text
    add_column :imports, :mapping, :json
  end
end
