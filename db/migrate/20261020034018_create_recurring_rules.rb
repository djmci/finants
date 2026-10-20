class CreateRecurringRules < ActiveRecord::Migration[8.1]
  def change
    create_table :recurring_rules do |t|
      t.string :payee, null: false
      t.references :account, null: false, foreign_key: true
      t.references :category, null: true, foreign_key: true
      t.references :to_account, null: true, foreign_key: { to_table: :accounts }
      t.string :kind, null: false, default: "expense"
      t.integer :amount_cents, null: false
      t.string :frequency, null: false
      t.integer :every, null: false, default: 1
      t.date :start_on, null: false
      t.date :end_on
      t.boolean :active, null: false, default: true

      t.timestamps
    end
  end
end
