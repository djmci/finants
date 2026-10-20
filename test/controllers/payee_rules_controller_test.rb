require "test_helper"

class PayeeRulesControllerTest < ActionDispatch::IntegrationTest
  test "update changes rule category and conditions" do
    sign_in_as users(:one)
    rule = PayeeRule.create!(pattern: "COLES", category: categories(:food))
    patch payee_rule_url(rule), params: { payee_rule: {
      pattern: "COLES GROUP", category_id: categories(:utilities).id,
      round_amount: "false", direction: "out", max_amount: "20", auto: "0"
    } }, headers: { "HTTP_REFERER" => categories_url(tab: "rules") }
    rule.reload
    assert_equal "COLES GROUP", rule.pattern
    assert_equal categories(:utilities), rule.category
    assert_equal false, rule.round_amount
    assert_equal "out", rule.direction
    assert_equal 2000, rule.max_amount_cents
    assert_equal false, rule.auto
  end

  test "destroy removes the rule" do
    sign_in_as users(:one)
    rule = PayeeRule.create!(pattern: "COLES", category: categories(:food))
    assert_difference "PayeeRule.count", -1 do
      delete payee_rule_url(rule), headers: { "HTTP_REFERER" => categories_url(tab: "rules") }
    end
  end

  test "non-auto rules suggest but never auto-categorise" do
    rule = PayeeRule.create!(pattern: "KMART", category: categories(:food), auto: false)
    assert_equal categories(:food), PayeeRule.for("KMART METRO", amount_cents: -100)
    assert_nil PayeeRule.for("KMART METRO", amount_cents: -100, auto_only: true)
  end
end
