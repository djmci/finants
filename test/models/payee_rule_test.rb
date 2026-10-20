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
end
