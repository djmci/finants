require "test_helper"

class TransactionsControllerTest < ActionDispatch::IntegrationTest
  test "redirects to sign in when logged out" do
    get transactions_url
    assert_redirected_to new_session_url
  end

  test "index lists transactions" do
    sign_in_as users(:one)
    get transactions_url
    assert_response :success
    assert_match "Woolworths", response.body
  end

  test "index filters to uncategorised" do
    sign_in_as users(:one)
    get transactions_url(uncategorised: 1)
    assert_match "UNKNOWN MERCHANT", response.body
    assert_no_match "Woolworths", response.body
  end

  test "create with expense direction stores negative cents" do
    sign_in_as users(:one)
    assert_difference "Transaction.count" do
      post transactions_url, params: { transaction: {
        account_id: accounts(:everyday).id, posted_on: "2026-10-15",
        payee: "Coles", amount: "45.20", direction: "expense",
        category_id: categories(:food).id
      } }, headers: { "HTTP_REFERER" => transactions_url }
    end
    txn = Transaction.order(:id).last
    assert_equal(-4520, txn.amount_cents)
    assert_equal users(:one), txn.user
  end

  test "create with income direction stores positive cents" do
    sign_in_as users(:one)
    post transactions_url, params: { transaction: {
      account_id: accounts(:everyday).id, posted_on: "2026-10-15",
      payee: "Refund", amount: "10.00", direction: "income"
    } }, headers: { "HTTP_REFERER" => transactions_url }
    assert_equal 1000, Transaction.order(:id).last.amount_cents
  end

  test "destroy removes the transfer pair too" do
    sign_in_as users(:one)
    out, into = Transaction.create_transfer!(
      from_account: accounts(:everyday), to_account: accounts(:savings),
      posted_on: Date.current, amount: "50", user: users(:one)
    )
    assert_difference "Transaction.count", -2 do
      delete transaction_url(out), headers: { "HTTP_REFERER" => transactions_url }
    end
  end

  test "index shows a clickable category guess for uncategorised rows" do
    sign_in_as users(:one)
    # A categorised sibling sharing the ref-stripped payee key → guess.
    Transaction.create!(account: accounts(:everyday), posted_on: Date.current,
                        payee: "UNKNOWN MERCHANT 991", amount_cents: -100,
                        category: categories(:food))
    get transactions_url
    assert_match "Tag as Food", response.body
  end

  test "update redirects back with an anchor to the edited row" do
    sign_in_as users(:one)
    txn = transactions(:pay)
    patch transaction_url(txn), params: { transaction: { payee: "Updated" } },
          headers: { "HTTP_REFERER" => transactions_url }
    assert_equal "#{transactions_url}#transaction_#{txn.id}", response.location
  end
end
