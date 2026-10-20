require "test_helper"

class TransfersControllerTest < ActionDispatch::IntegrationTest
  test "creates a linked pair" do
    sign_in_as users(:one)
    assert_difference "Transaction.count", 2 do
      post transfer_url, params: {
        from_account_id: accounts(:everyday).id,
        to_account_id: accounts(:savings).id,
        posted_on: "2026-10-15", amount: "200.00"
      }, headers: { "HTTP_REFERER" => transactions_url }
    end
    pair = Transaction.order(:id).last(2)
    assert_equal pair.first.transfer_pair_id, pair.last.transfer_pair_id
  end

  test "rejects same-account transfer" do
    sign_in_as users(:one)
    assert_no_difference "Transaction.count" do
      post transfer_url, params: {
        from_account_id: accounts(:everyday).id,
        to_account_id: accounts(:everyday).id,
        posted_on: "2026-10-15", amount: "200.00"
      }, headers: { "HTTP_REFERER" => transactions_url }
    end
  end
end
