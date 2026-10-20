require "test_helper"

class ForecastTest < ActiveSupport::TestCase
  setup do
    @account = Account.create!(name: "Proj", kind: "everyday", opening_balance_cents: 100000)
  end

  test "monthly expense rule descends the balance on the 15th" do
    rule = RecurringRule.create!(payee: "RENT", account: @account, kind: "expense",
                                 amount_cents: 100000, frequency: "monthly", every: 1,
                                 start_on: Date.new(2026, 1, 15))
    f = Forecast.new(accounts: [ @account ], rules: [ rule ])
    pts = f.series(Date.new(2026, 1, 1)..Date.new(2026, 2, 20))[@account]
    assert_equal 100000, pts.find { |d, _| d == Date.new(2026, 1, 14) }.last
    assert_equal 0, pts.find { |d, _| d == Date.new(2026, 1, 15) }.last
    assert_equal(-100000, pts.last.last) # second rent lands 15 Feb
  end

  test "transfer rule moves money between accounts, combined unchanged" do
    loan = Account.create!(name: "Loan", kind: "loan", opening_balance_cents: -50000000)
    rule = RecurringRule.create!(payee: "Loan Payment", account: @account,
                                 to_account: loan, kind: "transfer",
                                 amount_cents: 300000, frequency: "monthly", every: 1,
                                 start_on: Date.new(2026, 1, 10))
    f = Forecast.new(accounts: [ @account, loan ], rules: [ rule ])
    range = Date.new(2026, 1, 1)..Date.new(2026, 1, 31)
    series = f.series(range)
    assert_equal(-200000, series[@account].last.last) # 100000 - 300000
    assert_equal(-49700000, series[loan].last.last)   # -50000000 + 300000
    combined = f.combined(range)
    assert_equal(-49900000, combined.last.last) # total only fell by the (already-seeded) opening sums, no fake spend
  end

  test "discretionary spend drifts the projection down daily" do
    90.times do |i|
      Transaction.create!(account: @account, posted_on: Date.new(2026, 1, 1) - 90 + i,
                          payee: "SHOP #{i}", amount_cents: -1000)
    end
    f = Forecast.new(accounts: [ @account ], rules: [])
    pts = f.series(Date.new(2026, 1, 1)..Date.new(2026, 1, 10))[@account]
    # $10/day average outflow → balance falls 1000c/day
    assert_equal(-1000, pts.map(&:last).each_cons(2).sum { |a, b| b - a } / (pts.size - 1))
  end

  test "rule-linked and transfer transactions are excluded from discretionary" do
    rule = RecurringRule.create!(payee: "GYM", account: @account, kind: "expense",
                                 amount_cents: -4900, frequency: "weekly", every: 1,
                                 start_on: Date.new(2026, 1, 5))
    Transaction.create!(account: @account, posted_on: Date.new(2026, 1, 1) - 30,
                        payee: "GYM PTY", amount_cents: -4900, recurring_rule: rule)
    f = Forecast.new(accounts: [ @account ], rules: [ rule ])
    pts = f.series(Date.new(2026, 1, 1)..Date.new(2026, 1, 2))[@account]
    # No discretionary drift — only the weekly rule dips it on the 5th.
    assert_equal pts.first.last, pts.last.last
  end

  test "minimum finds the lowest projected point" do
    rule = RecurringRule.create!(payee: "RENT", account: @account, kind: "expense",
                                 amount_cents: 200000, frequency: "monthly", every: 1,
                                 start_on: Date.new(2026, 1, 15))
    f = Forecast.new(accounts: [ @account ], rules: [ rule ])
    date, cents = f.minimum(Date.new(2026, 1, 1)..Date.new(2026, 3, 31))
    assert_equal Date.new(2026, 3, 15), date # third rent lands; floor keeps falling
    assert_equal(-500000, cents)
  end
end
