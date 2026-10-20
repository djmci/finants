class ChangeImportPayloadToBinary < ActiveRecord::Migration[8.1]
  def change
    remove_column :imports, :payload, :text
    add_column :imports, :payload, :binary
  end
end
