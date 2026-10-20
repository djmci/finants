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
    assert_match "Forecast", response.body
    assert_match "Now", response.body
    assert_match "Near", response.body
    assert_match "Far", response.body
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
