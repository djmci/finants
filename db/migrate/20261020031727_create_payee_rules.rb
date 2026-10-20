class CreatePayeeRules < ActiveRecord::Migration[8.1]
  def change
    create_table :payee_rules do |t|
      t.string :pattern, null: false
      t.references :category, null: false, foreign_key: true

      t.timestamps

      t.index :pattern, unique: true
    end
  end
end
