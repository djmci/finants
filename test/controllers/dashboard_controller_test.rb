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
  end
end
