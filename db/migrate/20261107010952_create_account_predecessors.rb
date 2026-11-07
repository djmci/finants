class CreateAccountPredecessors < ActiveRecord::Migration[8.1]
  def change
    create_table :account_predecessors do |t|
      t.references :account, null: false, foreign_key: true
      t.references :predecessor, null: false, foreign_key: { to_table: :accounts }
    end
    add_index :account_predecessors, [ :account_id, :predecessor_id ], unique: true
  end
end
