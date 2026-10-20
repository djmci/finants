require "csv"

# Parses bank CSV exports into Transaction rows. Format presets are
# detected by header signature (never filename); the mapping is always
# user-overridable at preview time.
#
# Presets are best-effort — verify against real exports (PLAN phase 3).
class CsvImport
  ParseError = Class.new(StandardError)

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
      label: "HSBC AU",
      match: ->(h) { h.any? { |c| c.match?(/debit|withdrawal/) } &&
                     h.any? { |c| c.match?(/credit|deposit/) } },
      mapping: { "date" => nil, "payee" => nil, "debit" => nil, "credit" => nil, "sign" => "as_is" }
    },
    "qudos" => {
      label: "Qudos Bank",
      match: ->(h) { h.include?("transaction type") ||
                     (h.include?("narrative") && h.include?("balance")) },
      mapping: { "date" => nil, "payee" => nil, "debit" => nil, "credit" => nil, "sign" => "as_is" }
    }
  }.freeze

  DATE_FORMATS = [ "%d/%m/%Y", "%Y-%m-%d", "%d %b %Y", "%d-%m-%Y", "%m/%d/%Y" ].freeze

  attr_reader :headers, :rows

  def initialize(payload)
    table = CSV.parse(payload.to_s, headers: true, skip_blanks: true)
    @headers = table.headers.compact
    raise ParseError, "No header row found" if @headers.empty?
    @rows = table.map { |r| @headers.index_with { |h| r[h] } }
  rescue CSV::MalformedCSVError => e
    raise ParseError, e.message
  end

  def self.detect(headers)
    normalized = headers.map { |h| h.to_s.strip.downcase }
    PRESETS.find { |_k, p| p[:match].call(normalized) }&.first
  end

  # Prefill a column mapping for the given headers — preset first,
  # then generic column-name heuristics.
  def self.suggest(headers, format = nil)
    mapping = format ? PRESETS.dig(format, :mapping)&.dup || {} : {}
    guess = ->(patterns) { headers.find { |h| patterns.any? { |p| h.strip.match?(p) } } }
    mapping["date"]   ||= guess.call([ /\Adate\z/i, /date/i ])
    mapping["payee"]  ||= guess.call([ /desc|narrative|payee|details|merchant/i ])
    mapping["debit"]  ||= guess.call([ /debit|withdrawal|paid out/i ])
    mapping["credit"] ||= guess.call([ /credit|deposit|paid in/i ])
    unless mapping["debit"].present? && mapping["credit"].present?
      mapping["amount"] ||= guess.call([ /amount/i ])
    end
    mapping["sign"] ||= "as_is"
    mapping.compact
  end

  def preview(import, mapping)
    existing = Transaction.where(account: import.account).where.not(import_hash: nil)
                          .pluck(:import_hash).to_set
    rows.map do |r|
      parsed = parse_row(r, mapping)
      parsed.merge(duplicate: existing.include?(digest(import.account_id, r)),
                   category: PayeeRule.for(parsed[:payee]))
    end
  end

  def commit(import, mapping)
    existing = Transaction.where(account: import.account).where.not(import_hash: nil)
                          .pluck(:import_hash).to_set
    created = dupes = 0
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
          category: PayeeRule.for(parsed[:payee]),
          import_hash: hash
        )
        created += 1
      end
      import.update!(status: "committed", rows_count: created, mapping: mapping,
                     source_format: self.class.detect(headers) || "custom")
    end
    { created:, dupes: rows.size - created }
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
    str = value.to_s.strip
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
