require "test_helper"

class RecurringRuleTest < ActiveSupport::TestCase
  test "match_for finds rule by payee substring and amount magnitude" do
    match = RecurringRule.match_for(account: accounts(:everyday), payee: "LANDLORD RENT P/L SYDNEY", amount_cents: -200000)
    assert_equal recurring_rules(:rent), match
  end

  test "match_for ignores different amount or account" do
    assert_nil RecurringRule.match_for(account: accounts(:everyday), payee: "LANDLORD RENT", amount_cents: -150000)
    assert_nil RecurringRule.match_for(account: accounts(:savings), payee: "LANDLORD RENT", amount_cents: -200000)
  end

  test "match_for skips paused rules" do
    assert_nil RecurringRule.match_for(account: accounts(:everyday), payee: "OLD GYM PTY LTD", amount_cents: -4900)
  end

  test "transfer kind requires a different to_account" do
    rule = RecurringRule.new(payee: "Mortgage", account: accounts(:everyday), to_account: accounts(:everyday), kind: "transfer", amount_cents: 300000, frequency: "monthly", start_on: Date.current)
    assert_not rule.valid?
    rule.to_account = accounts(:savings)
    assert rule.valid?
  end

  test "signed_amount_cents negates expense only" do
    assert_equal(-200000, recurring_rules(:rent).signed_amount_cents)
    assert_equal 500000, recurring_rules(:paycheck).signed_amount_cents
    rule = RecurringRule.new(kind: "transfer", amount_cents: 300000)
    assert_equal 300000, rule.signed_amount_cents
  end

  test "transaction auto-links to matching rule" do
    txn = Transaction.create!(account: accounts(:everyday), posted_on: Date.current,
                              payee: "LANDLORD RENT P/L", amount_cents: -200000)
    assert_equal recurring_rules(:rent), txn.recurring_rule
  end

  test "matching a once rule resolves it" do
    rule = RecurringRule.create!(payee: "WEDDING GIFT", account: accounts(:everyday),
                                 kind: "expense", amount_cents: 50000,
                                 frequency: "once", every: 1, start_on: Date.current)
    Transaction.create!(account: accounts(:everyday), posted_on: Date.current,
                        payee: "WEDDING GIFT SHOP", amount_cents: -50000)
    assert_not rule.reload.active?
  end

  test "manual link to a once rule resolves it" do
    rule = RecurringRule.create!(payee: "CAR SERVICE", account: accounts(:everyday),
                                 kind: "expense", amount_cents: 85000,
                                 frequency: "once", every: 1, start_on: Date.current)
    txn = Transaction.create!(account: accounts(:everyday), posted_on: Date.current,
                              payee: "MIDAS SERVICE CENTRE", amount_cents: -84900)
    txn.update!(recurring_rule: rule) # approximate amount — matched by hand
    assert_not rule.reload.active?
  end
end
