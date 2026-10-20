class AddRecurringRuleToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_reference :transactions, :recurring_rule, null: true, foreign_key: true
  end
end
