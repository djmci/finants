class AddMaxAmountToPayeeRules < ActiveRecord::Migration[8.1]
  def change
    add_column :payee_rules, :max_amount_cents, :integer
    remove_index :payee_rules, [ :pattern, :round_amount ]
    add_index :payee_rules, [ :pattern, :round_amount, :max_amount_cents ], unique: true,
              name: "index_payee_rules_on_pattern_and_conditions"
  end
end
