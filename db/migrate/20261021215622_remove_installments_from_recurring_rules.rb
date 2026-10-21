class RemoveInstallmentsFromRecurringRules < ActiveRecord::Migration[8.1]
  def change
    remove_column :recurring_rules, :installments, :integer
  end
end
