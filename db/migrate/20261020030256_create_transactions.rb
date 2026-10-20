class CreateTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :transactions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :category, null: true, foreign_key: true
      t.references :import, null: true, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.date :posted_on, null: false
      t.string :payee
      t.integer :amount_cents, null: false
      t.text :notes
      t.string :transfer_pair_id
      t.string :import_hash

      t.timestamps

      t.index [ :account_id, :import_hash ], unique: true, where: "import_hash IS NOT NULL"
      t.index :posted_on
      t.index :transfer_pair_id
    end
  end
end
