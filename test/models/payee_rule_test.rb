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
end
