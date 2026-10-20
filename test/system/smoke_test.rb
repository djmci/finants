require "application_system_test_case"

class SmokeTest < ApplicationSystemTestCase
  test "signing in lands on the dashboard" do
    visit new_session_path
    fill_in "Email", with: users(:one).email_address
    fill_in "Password", with: "password"
    click_on "Sign in"

    assert_text "Dashboard"
  end

  test "signing in with a bad password stays on the form" do
    visit new_session_path
    fill_in "Email", with: users(:one).email_address
    fill_in "Password", with: "wrong"
    click_on "Sign in"

    assert_text "Try another email address or password."
  end

  test "signed-in user can open history" do
    visit new_session_path
    fill_in "Email", with: users(:one).email_address
    fill_in "Password", with: "password"
    click_on "Sign in"
    assert_text "Dashboard"

    visit transactions_path
    assert_text "History"
  end
end
