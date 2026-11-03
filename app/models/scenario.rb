# A what-if sandbox: a copy of the live rule set you can edit freely —
# add rules, change amounts, pause things — without touching the real
# forecast. The dashboard can overlay a scenario's projection for
# comparison.
class Scenario < ApplicationRecord
  has_many :recurring_rules, dependent: :destroy

  # Replace this scenario's rules with fresh copies of the live set.
  def clone_live_rules!
    clone_rules_from! RecurringRule.live
  end

  # Adopt this plan: its rules become the live set, and the displaced
  # live rules move into this scenario — a swap, so rule ids (and the
  # transactions matched to them) survive and it's fully reversible.
  def promote!
    mine = recurring_rules.to_a
    displaced = RecurringRule.live.to_a
    transaction do
      RecurringRule.live.update_all(scenario_id: id)
      RecurringRule.where(id: mine.map(&:id)).update_all(scenario_id: nil)
      retarget_transactions!(mine, displaced)
    end
  end

  # Replace this scenario's rules with copies of `source`.
  def clone_rules_from!(source)
    recurring_rules.destroy_all
    source.each do |r|
      recurring_rules.create!(r.attributes.except("id", "scenario_id", "created_at", "updated_at"))
    end
  end

  private

  # Transactions linked to a displaced live rule follow their successor
  # — same legs and payee key — so a posting keeps counting as "this
  # rule really happened" even when the adopted plan changed the amount.
  def retarget_transactions!(adopted, displaced)
    pool = displaced.group_by { |r| link_key(r) }
    adopted.each do |rule|
      old = pool[link_key(rule)]&.shift
      next unless old
      Transaction.where(recurring_rule_id: old.id).update_all(recurring_rule_id: rule.id)
      PayeeRule.where(recurring_rule_id: old.id).update_all(recurring_rule_id: rule.id)
    end
  end

  def link_key(rule)
    [ rule.account_id, rule.to_account_id, rule.kind, PayeeRule.detection_key(rule.payee) ]
  end
end
