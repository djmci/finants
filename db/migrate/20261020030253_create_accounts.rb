class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts do |t|
      t.string :name, null: false
      t.string :kind, null: false, default: "everyday"
      t.string :currency, null: false, default: "AUD"
      t.integer :opening_balance_cents, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.references :owner, null: true, foreign_key: { to_table: :users }
      t.text :notes

      t.timestamps
    end
  end
end
