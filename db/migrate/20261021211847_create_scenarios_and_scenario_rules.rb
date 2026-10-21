class CreateScenariosAndScenarioRules < ActiveRecord::Migration[8.1]
  def change
    create_table :scenarios do |t|
      t.string :name, null: false
      t.timestamps
    end

    add_reference :recurring_rules, :scenario, foreign_key: true
  end
end
