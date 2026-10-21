class RenameMaskHistoryToIncludeInHybrid < ActiveRecord::Migration[8.1]
  def change
    rename_column :recurring_rules, :mask_history, :include_in_hybrid
  end
end
