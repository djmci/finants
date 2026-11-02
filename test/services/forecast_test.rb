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
    # No discretionary drift — flat except the real txn on its day.
    assert_equal 95100, pts.last.last
    assert_equal pts.last.last, pts.find { |d, _| d == Date.new(2025, 12, 3) }.last
  end

  test "historical rows matching a transfer rule are not discretionary spend" do
    loan = Account.create!(name: "Loan", kind: "loan", opening_balance_cents: -50000000)
    rule = RecurringRule.create!(payee: "Loan Payment", account: @account,
                                 to_account: loan, kind: "transfer",
                                 amount_cents: 300000, frequency: "monthly", every: 1,
                                 start_on: Date.new(2026, 1, 10))
    # Unpaired historical repayment leg — matches the transfer rule.
    Transaction.create!(account: @account, posted_on: Date.new(2026, 1, 1) - 10,
                        payee: "Loan Payment TO: 102-431558-259", amount_cents: -300000)
    f = Forecast.new(accounts: [ @account ], rules: [ rule ])
    pts = f.series(Date.new(2026, 1, 1)..Date.new(2026, 1, 9))[@account]
    tail = pts.select { |d, _| d > Date.new(2025, 12, 22) }
    assert tail.all? { |_, v| v == tail.first.last }, "rule-matched spend must not drift the projection"
  end

  test "settle rule pays the target's balance monthly" do
    bank = @account # opening 1000.00
    amex = Account.create!(name: "Card", kind: "credit", opening_balance_cents: -200000)
    charge = RecurringRule.create!(payee: "SHOPS", account: amex, kind: "expense",
                                   amount_cents: 100000, frequency: "monthly", every: 1,
                                   start_on: Date.new(2026, 1, 1))
    settle = RecurringRule.create!(payee: "Card Payment", account: bank, to_account: amex,
                                   kind: "settle", frequency: "monthly", every: 1,
                                   start_on: Date.new(2026, 1, 15))
    f = Forecast.new(accounts: [ bank, amex ], rules: [ charge, settle ])
    pts = f.series(Date.new(2026, 1, 1)..Date.new(2026, 2, 20))

    # Jan 15: amex at -200000 - 100000 = -300000 → bank pays 3000, amex → 0.
    assert_equal(-200000, pts[bank].find { |d, _| d == Date.new(2026, 1, 15) }.last)
    assert_equal 0, pts[amex].find { |d, _| d == Date.new(2026, 1, 15) }.last
    # Feb 1 charge → -100000; Feb 15 settles it.
    assert_equal(-100000, pts[amex].find { |d, _| d == Date.new(2026, 2, 14) }.last)
    assert_equal 0, pts[amex].find { |d, _| d == Date.new(2026, 2, 15) }.last
    assert_equal(-300000, pts[bank].find { |d, _| d == Date.new(2026, 2, 15) }.last)
  end

  test "settle rule works when the target account is out of scope" do
    bank = @account
    amex = Account.create!(name: "Card", kind: "credit", opening_balance_cents: -200000)
    settle = RecurringRule.create!(payee: "Card Payment", account: bank, to_account: amex,
                                   kind: "settle", frequency: "monthly", every: 1,
                                   start_on: Date.new(2026, 1, 15))
    # Cash-view style: only the bank account is in scope, but the payment
    # still needs the Amex balance to size itself.
    f = Forecast.new(accounts: [ bank ], rules: [ settle ])
    pts = f.series(Date.new(2026, 1, 1)..Date.new(2026, 1, 31))[bank]
    assert_equal(-100000, pts.find { |d, _| d == Date.new(2026, 1, 15) }.last)
  end

  test "settle rules match transactions on payee regardless of amount" do
    bank = @account
    amex = Account.create!(name: "Card", kind: "credit", opening_balance_cents: 0)
    rule = RecurringRule.create!(payee: "AMEX PAYMENT", account: bank, to_account: amex,
                                 kind: "settle", frequency: "monthly", every: 1,
                                 start_on: Date.new(2026, 1, 15))
    assert_equal rule, RecurringRule.match_for(account: bank, payee: "AMEX PAYMENT THANK YOU", amount_cents: -12345)
  end

  test "a rule due after the last actual still projects" do
    # Actuals end Jan 10; the Jan 15 bill must project anyway — the
    # data ran out, not the obligation.
    Transaction.create!(account: @account, posted_on: Date.new(2026, 1, 10),
                        payee: "AMEX PAYMENT", amount_cents: -40000)
    rule = RecurringRule.create!(payee: "AMEX", account: @account, kind: "expense",
                                 amount_cents: 40000, frequency: "monthly", every: 1,
                                 start_on: Date.new(2026, 1, 15))
    pts = Forecast.new(accounts: [ @account ], rules: [ rule ])
                  .series(Date.new(2026, 2, 1)..Date.new(2026, 2, 20))[@account]
    assert_equal 60000,  pts.find { |d, _| d == Date.new(2026, 1, 14) }.last
    assert_equal 20000,  pts.find { |d, _| d == Date.new(2026, 1, 15) }.last
    assert_equal(-20000, pts.find { |d, _| d == Date.new(2026, 2, 15) }.last)
  end

  test "covered days replay actuals without double-counting the rule" do
    stale = Account.create!(name: "Stale", kind: "savings", opening_balance_cents: 0)
    Transaction.create!(account: stale, posted_on: Date.new(2026, 1, 5),
                        payee: "STALE", amount_cents: -1)
    rule = RecurringRule.create!(payee: "AMEX", account: @account, kind: "expense",
                                 amount_cents: 40000, frequency: "monthly", every: 1,
                                 start_on: Date.new(2026, 1, 15))
    Transaction.create!(account: @account, posted_on: Date.new(2026, 1, 15),
                        payee: "AMEX PAYMENT", amount_cents: -40000)
    Transaction.create!(account: @account, posted_on: Date.new(2026, 1, 31),
                        payee: "AMEX PAYMENT", amount_cents: -40000)
    # The walk starts Jan 6 (stale's data ran out) — inside @account's
    # coverage, where the Jan 15 occurrence is already a real debit.
    pts = Forecast.new(accounts: [ @account, stale ], rules: [ rule ])
                  .series(Date.new(2026, 2, 1)..Date.new(2026, 2, 20))[@account]
    assert_equal 100000, pts.find { |d, _| d == Date.new(2026, 1, 14) }.last
    assert_equal 60000,  pts.find { |d, _| d == Date.new(2026, 1, 15) }.last
    assert_equal 20000,  pts.find { |d, _| d == Date.new(2026, 2, 14) }.last
    assert_equal(-20000, pts.find { |d, _| d == Date.new(2026, 2, 15) }.last)
  end

  test "a settle due after the last actual still pays the walked balance" do
    amex = Account.create!(name: "Card", kind: "credit", opening_balance_cents: -200000)
    Transaction.create!(account: @account, posted_on: Date.new(2026, 1, 10),
                        payee: "AMEX PAYMENT", amount_cents: -1)
    settle = RecurringRule.create!(payee: "AMEX", account: @account, to_account: amex,
                                   kind: "settle", frequency: "monthly", every: 1,
                                   start_on: Date.new(2026, 1, 15))
    pts = Forecast.new(accounts: [ @account, amex ], rules: [ settle ])
                  .series(Date.new(2026, 2, 1)..Date.new(2026, 2, 20))
    assert_equal(-100001, pts[@account].find { |d, _| d == Date.new(2026, 1, 15) }.last)
    assert_equal 0, pts[amex].find { |d, _| d == Date.new(2026, 1, 15) }.last
    # Feb's settle is $0 — the card hasn't re-accrued.
    assert_equal(-100001, pts[@account].last.last)
  end

  test "a due-but-unposted occurrence inside posting lag still projects" do
    # Data runs through Jan 16 — the Jan 15 bill is inside the lag
    # window with no matching payment, so it's pending, not skipped.
    cat = Category.create!(name: "One-off", kind: "expense", exclude_from_forecast: true)
    Transaction.create!(account: @account, posted_on: Date.new(2026, 1, 16),
                        payee: "GROCER", amount_cents: -1, category: cat)
    rule = RecurringRule.create!(payee: "AMEX", account: @account, kind: "expense",
                                 amount_cents: 40000, frequency: "monthly", every: 1,
                                 start_on: Date.new(2026, 1, 15))
    pts = Forecast.new(accounts: [ @account ], rules: [ rule ])
                  .series(Date.new(2026, 2, 1)..Date.new(2026, 2, 20))[@account]
    assert_equal 60000, pts.find { |d, _| d == Date.new(2026, 1, 15) }.last
    assert_equal 19999, pts.find { |d, _| d == Date.new(2026, 2, 15) }.last
  end

  test "an occurrence matched by a late posting is skipped" do
    # The real debit posted a day late — the Jan 15 occurrence must
    # not apply on top of it.
    rule = RecurringRule.create!(payee: "AMEX", account: @account, kind: "expense",
                                 amount_cents: 40000, frequency: "monthly", every: 1,
                                 start_on: Date.new(2026, 1, 15))
    Transaction.create!(account: @account, posted_on: Date.new(2026, 1, 16),
                        payee: "AMEX PAYMENT", amount_cents: -40000)
    pts = Forecast.new(accounts: [ @account ], rules: [ rule ])
                  .series(Date.new(2026, 2, 1)..Date.new(2026, 2, 20))[@account]
    # Single application only — a double-count would leave 20000-40000.
    assert_equal 20000, pts.find { |d, _| d == Date.new(2026, 2, 15) }.last
  end

  test "an overdue once-rule stays pending at the data edge" do
    cat = Category.create!(name: "One-off", kind: "expense", exclude_from_forecast: true)
    Transaction.create!(account: @account, posted_on: Date.new(2026, 1, 10),
                        payee: "GROCER", amount_cents: -1, category: cat)
    rule = RecurringRule.create!(payee: "HSBC FINAL", account: @account, kind: "expense",
                                 amount_cents: 1600000, frequency: "once", every: 1,
                                 start_on: Date.new(2026, 1, 1))
    pts = Forecast.new(accounts: [ @account ], rules: [ rule ])
                  .series(Date.new(2026, 2, 1)..Date.new(2026, 2, 20))[@account]
    # Due Jan 1, never posted — relands at Jan 11 (day after the data).
    assert_equal(-1500001, pts.find { |d, _| d == Date.new(2026, 1, 11) }.last)
    assert_equal(-1500001, pts.last.last)
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
