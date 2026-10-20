require "test_helper"

class HealthControllerTest < ActionDispatch::IntegrationTest
  test "redirects to sign in when logged out" do
    get health_url
    assert_redirected_to new_session_url
  end

  test "renders report when signed in" do
    sign_in_as users(:one)
    get health_url
    assert_response :success
    assert_match "Bill coverage", response.body
    assert_match "Income vs spend", response.body
    assert_match "Where it goes", response.body
  end
end
