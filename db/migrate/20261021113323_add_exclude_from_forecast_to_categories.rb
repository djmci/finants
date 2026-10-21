class AddExcludeFromForecastToCategories < ActiveRecord::Migration[8.1]
  def change
    add_column :categories, :exclude_from_forecast, :boolean, default: false, null: false
  end
end
