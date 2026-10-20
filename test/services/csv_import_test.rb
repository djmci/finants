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

  test "detects qudos headers" do
    assert_equal "qudos", CsvImport.detect([ "Effective Date", "Entered Date", "Transaction Description", "Amount", "Balance" ])
  end

  test "qudos rows parse signed amounts and entered dates" do
    csv = CsvImport.new("Effective Date,Entered Date,Transaction Description,Amount,Balance\n,16/10/2026,Osko Payment To Foo,-$250.00,$1020.30\n")
    rows = csv.rows.map { |r| csv.parse_row(r, CsvImport.suggest(csv.headers, "qudos")) }
    assert_equal Date.new(2026, 10, 16), rows.first[:posted_on]
    assert_equal(-25000, rows.first[:amount_cents])
  end

  test "xlsx parses typed cells — dates as Date, amounts as cents" do
    payload = File.binread(file_fixture("hsbc_extract.xlsx"))
    csv = CsvImport.new(payload)
    assert csv.xlsx?
    assert_equal %w[Account Loan], csv.sheets
    assert_equal "hsbc", CsvImport.detect(csv.headers)
    rows = csv.rows.map { |r| csv.parse_row(r, CsvImport.suggest(csv.headers, "hsbc")) }
    assert_equal Date.new(2025, 7, 2), rows.first[:posted_on]
    assert_equal(-12900, rows.first[:amount_cents])
    assert_equal "AUSSIE BROADBAND", rows.first[:payee]
    assert_equal categories(:food), PayeeRule.for(rows.last[:payee])

    loan = CsvImport.new(payload, sheet: "Loan")
    assert_equal 1, loan.rows.size
    assert_equal(-472975, loan.parse_row(loan.rows.first, CsvImport.suggest(loan.headers, "hsbc"))[:amount_cents])
  end
end
