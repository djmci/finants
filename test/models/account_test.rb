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
end
