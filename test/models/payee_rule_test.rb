require "test_helper"

class PayeeRuleTest < ActiveSupport::TestCase
  test "for matches normalized substring" do
    assert_equal categories(:food), PayeeRule.for("WOOLWORTHS 1234 SYDNEY")
    assert_nil PayeeRule.for("SOME RANDOM SHOP")
  end

  test "learn normalizes and upserts" do
    PayeeRule.learn("Coles  Express", categories(:food))
    assert_equal categories(:food), PayeeRule.for("COLES EXPRESS")

    PayeeRule.learn("coles express", categories(:utilities))
    assert_equal categories(:utilities), PayeeRule.for("COLES EXPRESS")
    assert_equal 1, PayeeRule.where(pattern: "COLES EXPRESS").count
  end

  test "for prefers round_amount rules matching the amount's shape" do
    utilities = categories(:utilities)
    comm = Category.create!(name: "Comms", kind: "expense")
    PayeeRule.create!(pattern: "AGL RETAIL", category: utilities, round_amount: false)
    PayeeRule.create!(pattern: "AGL RETAIL", category: comm, round_amount: true)
    assert_equal comm, PayeeRule.for("AGL RETAIL ENERG", amount_cents: -5000)
    assert_equal utilities, PayeeRule.for("AGL RETAIL ENERG", amount_cents: -8206)
  end


  test "for respects direction conditions" do
    reim = Category.create!(name: "Reimb", kind: "expense")
    PayeeRule.create!(pattern: "OSKO PAYMENT FROM", direction: "in", category: reim)
    assert_equal reim, PayeeRule.for("OSKO PAYMENT FROM J BLOGGS", amount_cents: 10_000)
    assert_nil PayeeRule.for("OSKO PAYMENT FROM J BLOGGS", amount_cents: -10_000)
  end


  test "auto rule applies to uncategorised txns on save" do
    txn = Transaction.create!(account: accounts(:everyday), posted_on: Date.current,
                              payee: "KMART BURWOOD", amount_cents: -100)
    PayeeRule.create!(pattern: "KMART", category: categories(:food), auto: true)
    assert_equal categories(:food), txn.reload.category
  end

  test "suggest-only rule does not apply on save" do
    txn = Transaction.create!(account: accounts(:everyday), posted_on: Date.current,
                              payee: "BIGW", amount_cents: -100)
    PayeeRule.create!(pattern: "BIGW", category: categories(:food), auto: false)
    assert_nil txn.reload.category
  end


  test "learn_rule=false on a categorised txn writes no rule" do
    assert_no_difference "PayeeRule.count" do
      Transaction.create!(account: accounts(:everyday), posted_on: Date.current,
                          payee: "UNIQUE MERCHANT XYZ", amount_cents: -100,
                          category: categories(:food), learn_rule: false)
    end
  end

  test "coverage rows answer coverage_for but never categorisation" do
    rule = recurring_rules(:streaming)
    PayeeRule.create!(pattern: "NETFLIX", recurring_rule: rule)
    assert_nil PayeeRule.for("NETFLIX.COM 866-579-1234", amount_cents: -2299)
    assert_equal rule, PayeeRule.coverage_for("NETFLIX.COM 866-579-1234")
    assert_nil PayeeRule.coverage_for("SOME RANDOM SHOP")
  end

  test "coverage rows can also categorise" do
    rule = recurring_rules(:streaming)
    PayeeRule.create!(pattern: "NETFLIX", recurring_rule: rule, category: categories(:food))
    assert_equal categories(:food), PayeeRule.for("NETFLIX.COM 866-579-1234", amount_cents: -2299)
    assert_equal rule, PayeeRule.coverage_for("NETFLIX.COM 866-579-1234")
  end

  test "a payee rule needs a category or a forecast rule" do
    assert_not PayeeRule.new(pattern: "NOTHING").valid?
  end

  test "coverage_match claims covered payees on any account" do
    rule = recurring_rules(:streaming) # on amex
    PayeeRule.create!(pattern: "NETFLIX", recurring_rule: rule)
    assert_equal rule, RecurringRule.coverage_match(payee: "NETFLIX.COM 866-579-1234")
    assert_nil RecurringRule.coverage_match(payee: "SOME RANDOM SHOP")
  end

  test "coverage_match ignores paused and scenario rules" do
    rule = recurring_rules(:paused)
    PayeeRule.create!(pattern: "OLD GYM", recurring_rule: rule)
    assert_nil RecurringRule.coverage_match(payee: "OLD GYM PTY")
  end

  test "categorising a txn learns a rule by default" do
    assert_difference "PayeeRule.count", 1 do
      Transaction.create!(account: accounts(:everyday), posted_on: Date.current,
                          payee: "REPEAT MERCHANT ABC", amount_cents: -100,
                          category: categories(:food))
    end
  end
end
