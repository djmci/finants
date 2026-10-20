require "test_helper"

class CsvImportTest < ActiveSupport::TestCase
  AMEX_CSV = <<~CSV
    Date,Description,Card Member,Account #,Amount
    05/10/2026,WOOLWORTHS 1234,DAN,1234,85.40
    08/10/2026,TRANSPORT NSW,DAN,1234,4.60
  CSV

  DEBIT_CREDIT_CSV = <<~CSV
    Date,Description,Debit,Credit,Balance
    2026-10-01,EMPLOYER SALARY,,5000.00,6000.00
    2026-10-05,WOOLWORTHS METRO,85.40,,5914.60
  CSV

  test "detects amex by card member header" do
    assert_equal "amex", CsvImport.detect([ "Date", "Description", "Card Member", "Account #", "Amount" ])
  end

  test "detects hsbc-style by debit/credit pair" do
    assert_equal "hsbc", CsvImport.detect([ "Date", "Description", "Debit", "Credit", "Balance" ])
  end

  test "unknown headers return nil" do
    assert_nil CsvImport.detect([ "a", "b" ])
  end

  test "amex preset flips positive charges to expenses" do
    csv = CsvImport.new(AMEX_CSV)
    mapping = CsvImport.suggest(csv.headers, "amex")
    rows = csv.rows.map { |r| csv.parse_row(r, mapping) }
    assert_equal(-8540, rows.first[:amount_cents])
    assert_equal(-460, rows.last[:amount_cents])
    assert_equal Date.new(2026, 10, 5), rows.first[:posted_on]
  end

  test "debit/credit columns give signed amounts" do
    csv = CsvImport.new(DEBIT_CREDIT_CSV)
    mapping = CsvImport.suggest(csv.headers, CsvImport.detect(csv.headers))
    rows = csv.rows.map { |r| csv.parse_row(r, mapping) }
    assert_equal 500000, rows.first[:amount_cents]
    assert_equal(-8540, rows.last[:amount_cents])
  end

  test "commit creates deduped transactions with payee-rule categories" do
    import = Import.create!(user: users(:one), account: accounts(:everyday),
                            filename: "amex.csv", payload: AMEX_CSV)
    result = CsvImport.new(AMEX_CSV).commit(import, CsvImport.suggest(CsvImport.new(AMEX_CSV).headers, "amex"))
    assert_equal 2, result[:created]
    assert_equal 0, result[:dupes]
    assert_equal "committed", import.reload.status

    woolies = Transaction.order(:id).last(2).find { |t| t.payee =~ /WOOLWORTHS/ }
    assert_equal categories(:food), woolies.category
  end

  test "re-committing the same file skips every row" do
    import = Import.create!(user: users(:one), account: accounts(:everyday),
                            filename: "amex.csv", payload: AMEX_CSV)
    csv = CsvImport.new(AMEX_CSV)
    csv.commit(import, CsvImport.suggest(csv.headers, "amex"))

    import2 = Import.create!(user: users(:one), account: accounts(:everyday),
                             filename: "amex.csv", payload: AMEX_CSV)
    result = csv.commit(import2, CsvImport.suggest(csv.headers, "amex"))
    assert_equal 0, result[:created]
    assert_equal 2, result[:dupes]
  end

  test "destroying import removes its transactions" do
    import = Import.create!(user: users(:one), account: accounts(:everyday),
                            filename: "amex.csv", payload: AMEX_CSV)
    csv = CsvImport.new(AMEX_CSV)
    csv.commit(import, CsvImport.suggest(csv.headers, "amex"))
    assert_difference "Transaction.count", -2 do
      import.destroy!
    end
  end
end
