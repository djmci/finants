class AddMaxPerYearToRecurringRules < ActiveRecord::Migration[8.1]
  def change
    add_column :recurring_rules, :max_per_year, :integer
  end
end
