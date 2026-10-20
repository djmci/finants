class AddDirectionToPayeeRules < ActiveRecord::Migration[8.1]
  def change
    add_column :payee_rules, :direction, :string
    remove_index :payee_rules, name: "index_payee_rules_on_pattern_and_conditions"
    add_index :payee_rules, [ :pattern, :round_amount, :max_amount_cents, :direction ],
              unique: true, name: "index_payee_rules_on_pattern_and_conditions"
  end
end
