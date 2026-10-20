require "test_helper"

class HealthReportTest < ActiveSupport::TestCase
  test "monthly_cents normalizes rule frequencies" do
    rule = RecurringRule.new(amount_cents: 10_000, frequency: "weekly", every: 1)
    assert_in_delta 43_333, rule.monthly_cents, 1
    rule.frequency = "fortnightly"
    assert_in_delta 21_666, rule.monthly_cents, 1
    rule.frequency = "monthly"; rule.every = 3
    assert_in_delta 3_333, rule.monthly_cents, 1
    rule.frequency = "yearly"; rule.every = 1
    assert_in_delta 833, rule.monthly_cents, 1
    rule.frequency = "once"
    assert_equal 0, rule.monthly_cents
  end

  test "coverage is income over committed outflow" do
    report = HealthReport.new
    assert_in_delta report.monthly_income / report.monthly_committed, report.coverage, 0.001
    assert_operator report.monthly_income, :>=, 0
  end

  test "monthly trend buckets actual income and spend" do
    account = accounts(:everyday)
    month = (Date.current - 3.months).beginning_of_month
    Transaction.create!(account:, posted_on: month + 2, payee: "PAY", amount_cents: 500_000)
    Transaction.create!(account:, posted_on: month + 3, payee: "SHOP", amount_cents: -200_000)
    row = HealthReport.new.monthly_trend.find { |m| m[:month] == month }
    assert_equal 500_000, row[:income_cents]
    assert_equal 200_000, row[:spend_cents]
    assert_equal 300_000, row[:net_cents]
  end

  test "category spend attributes rule-matched txns to the rule's category" do
    account = accounts(:everyday)
    cat = categories(:utilities)
    RecurringRule.create!(payee: "POWER CO", account:, category: cat, kind: "expense",
                          amount_cents: -30_000, frequency: "monthly", every: 1, start_on: Date.current)
    Transaction.create!(account:, posted_on: Date.current, payee: "POWER CO INV 991", amount_cents: -30_000)
    row = HealthReport.new.category_spend.find { |name, _| name == cat.display_name }
    assert row, "expected spend under #{cat.display_name}"
    assert_equal 30_000 / 3, row.last.round  # 90d window → monthlyised
  end

  test "category spend nets reimbursements tagged with the spend's category" do
    account = accounts(:everyday)
    food = categories(:food)
    baseline = HealthReport.new.category_spend.find { |name, _| name == food.display_name }.last
    Transaction.create!(account:, posted_on: Date.current, payee: "DINNER", amount_cents: -10_000, category: food)
    Transaction.create!(account:, posted_on: Date.current, payee: "MATE PAYBACK", amount_cents: 4_000, category: food)
    row = HealthReport.new.category_spend.find { |name, _| name == food.display_name }
    assert_in_delta baseline + 6_000 / 3.0, row.last, 1
  end
end
