require "csv"
require "creek"
require "tempfile"

# Parses bank exports (CSV or xlsx) into Transaction rows. Format presets
# are detected by header signature (never filename); the column mapping
# is always user-overridable at preview time.
class CsvImport
  ParseError = Class.new(StandardError)

  XLSX_MAGIC = "PK\x03\x04".b
  EXCEL_EPOCH = Date.new(1899, 12, 30)

  # amount: single signed column. debit/credit: separate columns.
  # sign "flip" inverts the amount column (Amex shows spend positive).
  PRESETS = {
    "amex" => {
      label: "American Express",
      match: ->(h) { h.include?("card member") || h.include?("account #") ||
                     h == %w[date description amount] },
      mapping: { "date" => "Date", "payee" => "Description", "amount" => "Amount", "sign" => "flip" }
    },
    "hsbc" => {
      # Online CSV: " Transaction Date,Description,Amount,Balance," (BOM
      # + leading space + trailing empty column, cleaned on parse).
      # xlsx extract: Transaction Date/Detail/Amount/Balance.
      label: "HSBC",
      match: ->(h) { (h.include?("transaction date") && h.include?("balance")) ||
                     (h.any? { |c| c.match?(/debit|withdrawal/) } &&
                      h.any? { |c| c.match?(/credit|deposit/) }) },
      mapping: { "date" => "Transaction Date", "sign" => "as_is" }
    },
    "qudos" => {
      label: "Qudos Bank",
      match: ->(h) { h.include?("entered date") && h.include?("transaction description") },
      mapping: { "date" => "Entered Date", "payee" => "Transaction Description",
                 "amount" => "Amount", "sign" => "as_is" }
    }
  }.freeze

  DATE_FORMATS = [ "%d/%m/%Y", "%Y-%m-%d", "%d %b %Y", "%d-%m-%Y", "%m/%d/%Y" ].freeze

  attr_reader :headers, :rows, :sheet_name

  def initialize(payload, sheet: nil)
    @payload = payload.to_s.b.delete_prefix("\xEF\xBB\xBF".b)
    if xlsx?
      load_xlsx(sheet)
    else
      table = CSV.parse(@payload, headers: true, skip_blanks: true)
      raw = table.headers
      cleaned = raw.map { |h| h.to_s.dup.force_encoding(Encoding::UTF_8).sub(/\A\xEF\xBB\xBF|\uFEFF/, "").strip }
      @headers = cleaned.reject(&:empty?)
      @rows = table.map do |r|
        row = {}
        cleaned.each_with_index { |h, i| row[h] = r[raw[i]] if h.present? }
        row
      end
    end
    raise ParseError, "No header row found" if @headers.empty?
  rescue CSV::MalformedCSVError, Zip::Error => e
    raise ParseError, e.message
  end

  def xlsx? = @payload.start_with?(XLSX_MAGIC)

  def sheets
    xlsx? ? @book.sheets.map(&:name) : []
  end

  def self.detect(headers)
    normalized = headers.map { |h| h.to_s.strip.downcase }
    PRESETS.find { |_k, p| p[:match].call(normalized) }&.first
  end

  # Prefill a column mapping for the given headers — preset first,
  # heuristic fallback per missing/unknown column.
  def self.suggest(headers, format = nil)
    mapping = format ? PRESETS.dig(format, :mapping)&.dup || {} : {}
    guess = ->(patterns) { headers.find { |h| patterns.any? { |p| h.strip.match?(p) } } }
    %w[date payee amount debit credit balance].each do |k|
      mapping[k] = nil if mapping[k].present? && !headers.include?(mapping[k])
    end
    mapping["date"]   ||= guess.call([ /\Adate\z/i, /date/i ])
    mapping["payee"]  ||= guess.call([ /desc|narrative|payee|detail|merchant/i ])
    mapping["debit"]  ||= guess.call([ /debit|withdrawal|paid out/i ])
    mapping["credit"] ||= guess.call([ /credit|deposit|paid in/i ])
    unless mapping["debit"].present? && mapping["credit"].present?
      mapping["amount"] ||= guess.call([ /amount/i ])
    end
    mapping["balance"] ||= guess.call([ /balance|closing/i ])
    mapping["sign"] ||= "as_is"
    mapping.compact
  end

  def preview(import, mapping)
    existing = Transaction.where(account: import.account).where.not(import_hash: nil)
                          .pluck(:import_hash).to_set
    rows.map do |r|
      parsed = parse_row(r, mapping)
      parsed.merge(duplicate: existing.include?(digest(import.account_id, r)),
                   category: PayeeRule.for(parsed[:payee], amount_cents: parsed[:amount_cents]))
    end
  end

  def commit(import, mapping, set_balance: false)
    existing = Transaction.where(account: import.account).where.not(import_hash: nil)
                          .pluck(:import_hash).to_set
    created = 0
    batch_hashes = Set.new
    Import.transaction do
      rows.each do |raw|
        parsed = parse_row(raw, mapping)
        next if parsed[:error]
        hash = digest(import.account_id, raw)
        next if existing.include?(hash) || batch_hashes.include?(hash)
        batch_hashes << hash
        Transaction.create!(
          account: import.account, import: import, user: import.user,
          posted_on: parsed[:posted_on], payee: parsed[:payee],
          amount_cents: parsed[:amount_cents],
          category: PayeeRule.for(parsed[:payee], amount_cents: parsed[:amount_cents]),
          import_hash: hash
        )
        created += 1
      end
      reconcile_balance!(import.account, mapping) if set_balance && mapping["balance"].present?
      import.update!(status: "committed", rows_count: created, mapping: mapping,
                     source_format: self.class.detect(headers) || "custom")
    end
    { created:, dupes: rows.size - created }
  end

  # Sets the account's opening balance so that opening + file txns lands
  # exactly on the balance stated by the newest row in the file.
  def reconcile_balance!(account, mapping)
    parsed = rows.map { |r| parse_row(r, mapping) }.reject { |p| p[:error] }
    newest = parsed.max_by { |p| p[:posted_on] }
    return unless newest
    stated = parse_money(newest[:raw][mapping["balance"]])
    return unless stated
    total = parsed.sum { |p| p[:amount_cents] }
    account.update!(opening_balance_cents: stated - total)
  end

  def parse_row(raw, mapping)
    date_raw = raw[mapping["date"]]
    posted_on = parse_date(date_raw)
    payee = raw[mapping["payee"]].to_s.strip.presence
    cents = cents_for(raw, mapping)
    error = if posted_on.nil? then "bad date: #{date_raw.inspect}"
    elsif cents.nil? then "bad amount"
    end
    { posted_on:, payee:, amount_cents: cents, error:, raw: }
  end

  private

  def load_xlsx(sheet)
    # The tempfile must outlive the CsvImport — creek re-reads the zip on
    # each sheet access. GC unlinks it with the importer object.
    @tmpfile = Tempfile.new([ "import", ".xlsx" ])
    @tmpfile.binmode.write(@payload)
    @tmpfile.flush
    @book = Creek::Book.new(@tmpfile.path)
    target = @book.sheets.find { |s| s.name == sheet } || @book.sheets.first
    @sheet_name = target.name
    cols = nil
    @headers = []
    @rows = []
    target.rows.each do |row|
      by_col = row.transform_keys { |k| k.sub(/\d+\z/, "") }
      if cols.nil?
        cols = by_col.keys.sort_by { |c| col_index(c) }
        @headers = cols.map { |c| by_col[c].to_s.strip }
      else
        @rows << @headers.zip(cols.map { |c| by_col[c] }).to_h
      end
    end
  end

  # "A" => 0, "B" => 1, "AA" => 26
  def col_index(letter)
    letter.chars.reduce(0) { |n, ch| n * 26 + (ch.ord - 64) } - 1
  end

  def cents_for(raw, mapping)
    if mapping["debit"].present? || mapping["credit"].present?
      debit = parse_money(raw[mapping["debit"]]) || 0
      credit = parse_money(raw[mapping["credit"]]) || 0
      credit - debit
    else
      v = parse_money(raw[mapping["amount"]])
      v &&= -v if mapping["sign"] == "flip"
      v
    end
  end

  def parse_date(value)
    return nil if value.blank?
    return value.to_date if value.respond_to?(:to_date) && !value.is_a?(String)
    str = value.to_s.strip
    if str.match?(/\A\d{5}\z/) && str.to_i.between?(40000, 60000)
      return EXCEL_EPOCH + str.to_i
    end
    DATE_FORMATS.each do |fmt|
      begin
        return Date.strptime(str, fmt)
      rescue ArgumentError
      end
    end
    Date.parse(str) rescue nil
  end

  def parse_money(value)
    return nil if value.blank?
    return (value * 100).round.to_i if value.is_a?(Numeric)
    str = value.to_s.strip.gsub(/[$,\s]/, "")
    negative = str.start_with?("-") || (str.start_with?("(") && str.end_with?(")"))
    digits = str.gsub(/[^0-9.]/, "")
    return nil if digits.empty?
    cents = (BigDecimal(digits) * 100).round.to_i
    negative ? -cents.abs : cents
  end

  def digest(account_id, raw)
    Digest::SHA256.hexdigest("#{account_id}|#{raw.values.join("|")}")[0, 32]
  end
end
