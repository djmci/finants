require "test_helper"

class RecurringSuggestionsTest < ActiveSupport::TestCase
  setup do
    @account = Account.create!(name: "Det", kind: "everyday", opening_balance_cents: 0)
  end

  def make(payee:, cents:, dates:)
    dates.each do |d|
      Transaction.create!(account: @account, posted_on: d, payee:, amount_cents: cents)
    end
  end

  test "monthly payee with per-txn refs is detected" do
    make(payee: "GYM DIRECT DEBIT 001", cents: -4900,
         dates: [ Date.new(2026, 7, 15), Date.new(2026, 8, 15), Date.new(2026, 9, 15) ])
    make(payee: "GYM DIRECT DEBIT 002", cents: -4900, dates: [ Date.new(2026, 10, 15) ])
    s = RecurringSuggestions.call.find { |x| x[:payee].include?("GYM") }
    assert s, "expected a GYM suggestion"
    assert_equal "monthly", s[:frequency]
    assert_equal 1, s[:every]
    assert_equal(-4900, s[:amount_cents])
    assert_equal "expense", s[:kind]
    assert_equal Date.new(2026, 10, 15), s[:last_on]
  end

  test "fortnightly interval detected" do
    dates = [ Date.new(2026, 9, 4), Date.new(2026, 9, 18), Date.new(2026, 10, 2), Date.new(2026, 10, 16) ]
    make(payee: "PAYROLL PTY", cents: 500000, dates:)
    s = RecurringSuggestions.call.find { |x| x[:payee].include?("PAYROLL") }
    assert_equal "fortnightly", s[:frequency]
    assert_equal "income", s[:kind]
  end

  test "irregular spend not suggested" do
    make(payee: "CAFE A", cents: -800,
         dates: [ Date.new(2026, 8, 3), Date.new(2026, 8, 20), Date.new(2026, 10, 9) ])
    assert_nil RecurringSuggestions.call.find { |x| x[:payee].include?("CAFE") }
  end

  test "payees covered by an existing rule are not suggested" do
    RecurringRule.create!(payee: "GYM", account: @account, kind: "expense",
                          amount_cents: -4900, frequency: "monthly", every: 1,
                          start_on: Date.new(2026, 7, 15))
    make(payee: "GYM DIRECT DEBIT 001", cents: -4900,
         dates: [ Date.new(2026, 7, 15), Date.new(2026, 8, 15), Date.new(2026, 9, 15) ])
    assert_nil RecurringSuggestions.call.find { |x| x[:payee].include?("GYM") }
  end

  test "fewer than three occurrences not suggested" do
    make(payee: "RARE SHOP", cents: -5000,
         dates: [ Date.new(2026, 8, 15), Date.new(2026, 9, 15) ])
    assert_nil RecurringSuggestions.call.find { |x| x[:payee].include?("RARE") }
  end

  test "loan account legs are not suggested" do
    loan = Account.create!(name: "DetLoan", kind: "loan", opening_balance_cents: -1000000)
    [ Date.new(2026, 7, 15), Date.new(2026, 8, 15), Date.new(2026, 9, 15) ].each do |d|
      Transaction.create!(account: loan, posted_on: d, payee: "INTEREST DEBIT X1", amount_cents: -5000)
    end
    assert_nil RecurringSuggestions.call.find { |x| x[:account_id] == loan.id }
  end
end
