class AddInstallmentsToRecurringRules < ActiveRecord::Migration[8.1]
  def change
    add_column :recurring_rules, :installments, :integer
  end
end
