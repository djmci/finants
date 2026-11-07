require "test_helper"

class AccountsControllerTest < ActionDispatch::IntegrationTest
  test "redirects to sign in when logged out" do
    get accounts_url
    assert_redirected_to new_session_url
  end

  test "index lists active accounts" do
    sign_in_as users(:one)
    get accounts_url
    assert_response :success
    assert_match "Everyday", response.body
    assert_no_match "Old Account", response.body
  end

  test "create adds an account with dollar opening balance" do
    sign_in_as users(:one)
    assert_difference "Account.count" do
      post accounts_url, params: { account: { name: "Qudos", kind: "savings", currency: "AUD", owner_id: "", opening_balance: "1000.50" } }, headers: { "HTTP_REFERER" => accounts_url }
    end
    assert_equal 100050, Account.order(:id).last.opening_balance_cents
  end

  test "archive flips active" do
    sign_in_as users(:one)
    post archive_account_url(accounts(:everyday)), headers: { "HTTP_REFERER" => accounts_url }
    assert_not accounts(:everyday).reload.active?
  end

  test "update with a successor hands the account over" do
    sign_in_as users(:one)
    successor = accounts(:savings)
    patch account_url(accounts(:everyday)),
          params: { account: { name: "Everyday" }, succeeded_by_id: successor.id, closed_on: "2026-11-10" },
          headers: { "HTTP_REFERER" => accounts_url }
    old = accounts(:everyday).reload
    assert_not old.active?
    assert_equal 0, old.balance_cents(on: Date.new(2026, 11, 10))
    assert_includes successor.predecessors, old
    assert_equal successor, recurring_rules(:rent).reload.account
  end

  test "update with close leaves no successor" do
    sign_in_as users(:one)
    patch account_url(accounts(:everyday)),
          params: { account: { name: "Everyday" }, succeeded_by_id: "close" },
          headers: { "HTTP_REFERER" => accounts_url }
    old = accounts(:everyday).reload
    assert_not old.active?
    assert_equal 0, old.balance_cents
    assert_empty AccountPredecessor.where(predecessor: old)
  end
end
