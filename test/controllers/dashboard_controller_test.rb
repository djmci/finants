require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "index redirects to sign in when logged out" do
    get root_url
    assert_redirected_to new_session_url
  end

  test "index renders when signed in" do
    sign_in_as users(:one)
    get root_url
    assert_response :success
    assert_match "Cashflow forecast — Cashflow", response.body
  end

  test "index supports net-worth and per-account scopes" do
    sign_in_as users(:one)
    get root_url(account: "all")
    assert_response :success
    assert_match "Cashflow forecast — Net worth", response.body

    get root_url(account: accounts(:everyday).id)
    assert_response :success
    assert_match "Cashflow forecast — Everyday", response.body
  end
end
