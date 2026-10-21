# A what-if sandbox: a copy of the live rule set you can edit freely —
# add rules, change amounts, pause things — without touching the real
# forecast. The dashboard can overlay a scenario's projection for
# comparison.
class Scenario < ApplicationRecord
  has_many :recurring_rules, dependent: :destroy

  # Replace this scenario's rules with fresh copies of the live set.
  def clone_live_rules!
    recurring_rules.destroy_all
    RecurringRule.live.each do |r|
      recurring_rules.create!(r.attributes.except("id", "scenario_id", "created_at", "updated_at"))
    end
  end
end
