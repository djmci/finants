require "test_helper"

class TransactionTest < ActiveSupport::TestCase
  test "amount= parses dollars to cents" do
    txn = Transaction.new(account: accounts(:everyday), posted_on: Date.current, amount: "12.34")
    assert_equal 1234, txn.amount_cents
  end

  test "amount= with blank leaves cents nil so validation fails" do
    txn = Transaction.new(account: accounts(:everyday), posted_on: Date.current, amount: "")
    assert_not txn.valid?
    assert_includes txn.errors[:amount_cents], "can't be blank"
  end

  test "zero amount is invalid" do
    txn = Transaction.new(account: accounts(:everyday), posted_on: Date.current, amount: "0.00")
    assert_not txn.valid?
  end

  test "create_transfer! links a signed pair" do
    pair = Transaction.create_transfer!(
      from_account: accounts(:everyday), to_account: accounts(:savings),
      posted_on: Date.current, amount: "250.00", user: users(:one)
    )
    out, into = pair.to_a.sort_by(&:amount_cents)
    assert_equal -25000, out.amount_cents
    assert_equal 25000, into.amount_cents
    assert_equal out.transfer_pair_id, into.transfer_pair_id
    assert_equal into, out.transfer_pair
  end

  test "transfer does not change combined balance" do
    before = accounts(:everyday).balance_cents + accounts(:savings).balance_cents
    Transaction.create_transfer!(
      from_account: accounts(:everyday), to_account: accounts(:savings),
      posted_on: Date.current, amount: "100", user: users(:one)
    )
    after = accounts(:everyday).balance_cents + accounts(:savings).balance_cents
    assert_equal before, after
  end

  test "uncategorised scope" do
    assert_includes Transaction.uncategorised, transactions(:mystery_spend)
    assert_not_includes Transaction.uncategorised, transactions(:groceries)
  end
end
