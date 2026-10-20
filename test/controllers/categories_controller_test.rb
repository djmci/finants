require "test_helper"

class CategoriesControllerTest < ActionDispatch::IntegrationTest
  test "new renders inline form for a drawer" do
    sign_in_as users(:one)
    get new_category_url(select_id: "transaction_category_id")
    assert_response :success
    assert_match "new_category_frame", response.body
    assert_match "Category name", response.body
  end

  test "new with cancel renders just the link" do
    sign_in_as users(:one)
    get new_category_url(cancel: 1)
    assert_response :success
    assert_match "+ New category", response.body
    assert_no_match(/form/, response.body)
  end

  test "turbo_stream create appends option to target select" do
    sign_in_as users(:one)
    post categories_url(format: :turbo_stream),
         params: { category: { name: "Pets", kind: "expense" }, select_id: "transaction_category_id" }
    assert_response :success
    assert_match "turbo-stream", response.body
    assert_match "transaction_category_id", response.body
    assert_match "Pets", response.body
    assert_equal "Pets", Category.find_by(name: "Pets").name
  end
end
