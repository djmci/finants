class AddAutoToPayeeRules < ActiveRecord::Migration[8.1]
  def change
    add_column :payee_rules, :auto, :boolean, default: true, null: false
  end
end
