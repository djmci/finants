require "test_helper"

class ImportsControllerTest < ActionDispatch::IntegrationTest
  CSV_BODY = "Date,Description,Amount\n05/10/2026,WOOLWORTHS,85.40\n"

  test "upload stores a draft import" do
    sign_in_as users(:one)
    file = Rack::Test::UploadedFile.new(StringIO.new(CSV_BODY), "text/csv", original_filename: "export.csv")
    assert_difference "Import.count" do
      post imports_url, params: { account_id: accounts(:everyday).id, file: file }
    end
    import = Import.order(:id).last
    assert_equal "draft", import.status
    assert_redirected_to import_url(import)
  end

  test "commit creates transactions" do
    sign_in_as users(:one)
    import = Import.create!(user: users(:one), account: accounts(:everyday),
                            filename: "x.csv", payload: CSV_BODY)
    assert_difference "Transaction.count", 1 do
      post commit_import_url(import), params: { mapping: { date: "Date", payee: "Description", amount: "Amount", sign: "flip" } }
    end
    assert_equal "committed", import.reload.status
    assert_equal(-8540, Transaction.order(:id).last.amount_cents)
  end

  test "destroy removes the batch" do
    sign_in_as users(:one)
    import = Import.create!(user: users(:one), account: accounts(:everyday),
                            filename: "x.csv", payload: CSV_BODY)
    post commit_import_url(import), params: { mapping: { date: "Date", payee: "Description", amount: "Amount", sign: "flip" } }
    assert_difference "Transaction.count", -1 do
      delete import_url(import)
    end
  end
end
