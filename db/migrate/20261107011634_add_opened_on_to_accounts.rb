class AddOpenedOnToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :opened_on, :date
  end
end
