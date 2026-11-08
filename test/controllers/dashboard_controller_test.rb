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

  test "custom range clips history and projection to from/to" do
    sign_in_as users(:one)
    get root_url(from: (Date.current - 10.days).to_s, to: (Date.current + 20.days).to_s)
    assert_response :success
    # The chart's axis endpoints are the requested window, not the
    # default 90-day history + 6-month horizon.
    assert_match (Date.current - 10.days).strftime("%-d %b %y").upcase, response.body
    assert_match (Date.current + 20.days).strftime("%-d %b %y").upcase, response.body
    assert_no_match (Date.current - 90.days).strftime("%-d %b %y").upcase, response.body
  end

  test "a range entirely in the past still shows history" do
    sign_in_as users(:one)
    get root_url(from: (Date.current - 120.days).to_s, to: (Date.current - 60.days).to_s)
    assert_response :success
    # min_d axis label is the `from` date — the window reaches back
    # past the default 90-day history.
    assert_match (Date.current - 120.days).strftime("%-d %b %y").upcase, response.body
  end

  test "a from date after today empties history without error" do
    sign_in_as users(:one)
    get root_url(from: (Date.current + 8.days).to_s, to: (Date.current + 3.months).to_s)
    assert_response :success
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
