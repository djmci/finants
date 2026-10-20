class CreateImports < ActiveRecord::Migration[8.1]
  def change
    create_table :imports do |t|
      t.references :user, null: false, foreign_key: true
      t.references :account, null: true, foreign_key: true
      t.string :filename
      t.string :source_format
      t.integer :rows_count, null: false, default: 0

      t.timestamps
    end
  end
end
