require "test_helper"

class RecurringRulesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @rule = recurring_rules(:streaming) # on amex
  end

  test "index renders the coverage section when editing a rule" do
    PayeeRule.create!(pattern: "NETFLIX", recurring_rule: @rule)
    get recurring_rules_url(edit: @rule.id)
    assert_response :success
    assert_match "Covered payees", response.body
    assert_match "NETFLIX", response.body
  end

  test "link_payee records coverage and links matching transactions" do
    txn = Transaction.create!(account: accounts(:amex), posted_on: Date.current,
                              payee: "THE COUNCIL OF ST AN TH SYDNEY", amount_cents: -183450,
                              learn_rule: false)
    cross = Transaction.create!(account: accounts(:everyday), posted_on: Date.current,
                                payee: "THE COUNCIL OF ST AN TH SYDNEY", amount_cents: -5000,
                                learn_rule: false)
    other = Transaction.create!(account: accounts(:amex), posted_on: Date.current,
                                payee: "WOOLWORTHS METRO", amount_cents: -8000,
                                learn_rule: false)
    post link_payee_recurring_rule_url(@rule), params: { payee: "THE COUNCIL OF ST AN TH SYDNEY" }
    assert_redirected_to recurring_rules_path(edit: @rule.id)

    coverage = @rule.payee_rules.first
    assert_equal "THE COUNCIL OF ST AN TH SYDNEY", coverage.pattern
    assert_equal @rule, txn.reload.recurring_rule
    assert_equal @rule, cross.reload.recurring_rule # coverage spans accounts
    assert_nil other.reload.recurring_rule
  end

  test "unlink_payee removes coverage and unlinks matching transactions" do
    PayeeRule.create!(pattern: "COUNCIL OF ST AN", recurring_rule: @rule)
    txn = Transaction.create!(account: accounts(:amex), posted_on: Date.current,
                              payee: "THE COUNCIL OF ST AN TH SYDNEY", amount_cents: -183450,
                              recurring_rule: @rule, learn_rule: false)
    coverage = @rule.payee_rules.first
    delete unlink_payee_recurring_rule_url(@rule), params: { payee_rule_id: coverage.id }
    assert_redirected_to recurring_rules_path(edit: @rule.id)
    assert_nil PayeeRule.find_by(id: coverage.id)
    assert_nil txn.reload.recurring_rule
  end
end
