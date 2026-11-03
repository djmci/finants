require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "index renders the landing page when logged out" do
    get root_url
    assert_response :success
  end

  test "index renders when signed in" do
    sign_in_as users(:one)
    get root_url
    assert_response :success
    assert_match "Forecast", response.body
    assert_match "Cash on hand", response.body
    assert_match "Next month", response.body
    assert_match "Next quarter", response.body
    assert_match "Next year", response.body
  end

  test "calendar shows a once-rule only in its due month" do
    sign_in_as users(:one)
    RecurringRule.create!(payee: "EQUITY TOP UP", account: accounts(:everyday), kind: "income",
                          amount_cents: 4_000_000, frequency: "once",
                          start_on: Date.current.next_month.beginning_of_month)
    get root_url(upcoming: "calendar", cal_month: Date.current.next_month.strftime("%Y-%m"))
    assert_match "EQUITY", response.body
    get root_url(upcoming: "calendar", cal_month: (Date.current + 2.months).strftime("%Y-%m"))
    assert_no_match "EQUITY", response.body
  end

  test "index scopes to any single account" do
    sign_in_as users(:one)
    get root_url(account: accounts(:everyday).id)
    assert_response :success
    assert_match "Forecast — Everyday", response.body
    get root_url(account: accounts(:amex).id)
    assert_response :success
    assert_match "Forecast — Amex", response.body
  end
end
