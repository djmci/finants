class AddRecurringRuleToPayeeRules < ActiveRecord::Migration[8.1]
  def change
    add_reference :payee_rules, :recurring_rule, foreign_key: true
    change_column_null :payee_rules, :category_id, true
  end
end
