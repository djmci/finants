class AddRoundAmountToPayeeRules < ActiveRecord::Migration[8.1]
  def change
    add_column :payee_rules, :round_amount, :boolean
    remove_index :payee_rules, :pattern
    add_index :payee_rules, [ :pattern, :round_amount ], unique: true
  end
end
