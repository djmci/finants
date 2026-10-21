class AddMaskHistoryToRecurringRules < ActiveRecord::Migration[8.1]
  def change
    add_column :recurring_rules, :mask_history, :boolean, default: true, null: false
  end
end
