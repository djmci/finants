require "test_helper"

class AccountTest < ActiveSupport::TestCase
  test "balance is opening plus transaction sum" do
    account = accounts(:everyday)
    assert_equal 100000 + 500000 - 8540, account.balance_cents
  end

  test "balance on a date ignores later transactions" do
    account = accounts(:everyday)
    assert_equal 100000 + 500000, account.balance_cents(on: Date.new(2026, 10, 2))
  end

  test "balance is zero before opened_on" do
    account = Account.create!(name: "New", kind: "everyday",
                              opening_balance_cents: 50000, opened_on: Date.new(2026, 11, 7))
    assert_equal 0, account.balance_cents(on: Date.new(2026, 11, 6))
    assert_equal 50000, account.balance_cents(on: Date.new(2026, 11, 7))
    assert_equal 50000, account.balance_cents
  end

  test "owner_label falls back to Joint" do
    assert_equal "Dan", accounts(:everyday).owner_label
    assert_equal "Joint", accounts(:savings).owner_label
  end

  test "running_balances accumulates in posted order" do
    balances = accounts(:everyday).running_balances
    assert_equal 600000, balances[transactions(:pay).id]
    assert_equal 591460, balances[transactions(:groceries).id]
  end

  test "kind must be known" do
    assert_not Account.new(name: "X", kind: "bogus").valid?
  end

  test "handover zeroes the old account, repoints rules, links the successor" do
    old = accounts(:everyday) # balance 591460 via fixtures
    rule = recurring_rules(:rent)
    successor = Account.create!(name: "New Bank", kind: "everyday", opening_balance_cents: 50000)

    old.handover_to!(successor, on: Date.new(2026, 11, 10))

    assert_equal 0, old.balance_cents
    assert_not old.reload.active?
    assert_includes successor.reload.predecessors, old
    assert_equal Date.new(2026, 11, 10), successor.opened_on
    assert_equal successor, rule.reload.account
    closure = old.transactions.order(:posted_on).last
    assert_equal "Account closure adjustment", closure.payee
    assert_equal(-591460, closure.amount_cents)
    assert closure.category.exclude_from_forecast?
  end

  test "handover skips the adjustment when already zero" do
    old = Account.create!(name: "Empty", kind: "everyday")
    successor = accounts(:savings)
    assert_no_difference -> { Transaction.count } do
      old.handover_to!(successor)
    end
  end

  test "link_successor attaches a successor after closure" do
    old = Account.create!(name: "Dead", kind: "everyday", active: false)
    rule = RecurringRule.create!(payee: "GYM", account: old, kind: "expense",
                                 amount_cents: 4900, frequency: "weekly", every: 1,
                                 start_on: Date.new(2026, 1, 5))
    successor = accounts(:savings)
    old.link_successor!(successor, on: Date.new(2026, 11, 6))
    assert_includes old.successors, successor
    assert_equal successor, rule.reload.account
    assert_equal Date.new(2026, 11, 6), successor.opened_on
  end

  test "redate_closure moves the adjustment and the successor's open date" do
    old = accounts(:everyday)
    successor = Account.create!(name: "New Bank", kind: "everyday", opening_balance_cents: 1000)
    old.handover_to!(successor, on: Date.new(2026, 11, 10))
    old.redate_closure!(Date.new(2026, 11, 6))
    closure = old.transactions.where(payee: Account::CLOSURE_PAYEE).first
    assert_equal Date.new(2026, 11, 6), closure.posted_on
    assert_equal Date.new(2026, 11, 6), successor.reload.opened_on
  end

  test "source_ids walks the predecessor graph" do
    mid = Account.create!(name: "Mid", kind: "everyday")
    mid.account_predecessors.create!(predecessor: accounts(:old_account))
    top = Account.create!(name: "Top", kind: "everyday")
    top.account_predecessors.create!(predecessor: mid)
    top.account_predecessors.create!(predecessor: accounts(:savings))
    assert_equal [ mid.id, accounts(:old_account).id, accounts(:savings).id ].sort,
                 (top.source_ids - [ top.id ]).sort
  end
end
