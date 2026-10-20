# Detects recurring patterns in imported transactions: payees that
# repeat on a regular interval become suggested RecurringRules.
class RecurringSuggestions
  MIN_OCCURRENCES = 3

  # Median day-gap → [frequency, every]
  INTERVALS = [
    [ 5..9,    "weekly",      1 ],
    [ 11..17,  "fortnightly", 1 ],
    [ 25..35,  "monthly",     1 ],
    [ 80..100, "monthly",     3 ],
    [ 170..195, "monthly",    6 ],
    [ 350..380, "yearly",     1 ]
  ].freeze

  def self.call = new.suggest

  # [{payee, account, amount_cents, frequency, every, kind,
  #   count, last_on, next_on}]
  def suggest
    existing = RecurringRule.active.includes(:account).to_a
    suggestions = []
    transaction_groups.each do |(account_id, key), txns|
      dates = txns.map(&:posted_on).uniq.sort
      next if dates.size < MIN_OCCURRENCES
      median = median_gap(dates)
      interval = INTERVALS.find { |range, _, _| range.include?(median) }
      next unless interval
      next if key.blank? || covered?(existing, account_id, key)

      txns_by_amount = txns.group_by(&:amount_cents)
      amount = txns_by_amount.max_by { |_c, ts| ts.size }.first
      suggestions << {
        payee: suggested_payee(txns),
        account_id:,
        amount_cents: amount,
        kind: amount.negative? ? "expense" : "income",
        frequency: interval[1],
        every: interval[2],
        count: dates.size,
        last_on: dates.last,
        next_on: dates.last + median
      }
    end
    suggestions.sort_by { |s| -s[:count] }
  end

  private

  # Groups by a ref-stripped key: bank descriptions carry per-txn refs
  # (ZAL104384, APP#…, timestamps, account numbers) that defeat exact
  # payee grouping — drop every token containing a digit.
  # Loan accounts are skipped: their legs are mirrors of the paying
  # account's (repayments) or debt accrual (interest) — not cashflow.
  def transaction_groups
    Transaction.excluding_transfers.where.not(payee: [ nil, "" ])
               .joins(:account).where.not(accounts: { kind: "loan" })
               .includes(:account)
               .group_by { |t| [ t.account_id, PayeeRule.detection_key(t.payee) ] }
  end

  # Longest common prefix of the group's normalized payees, cut at a
  # word boundary — a clean rule pattern that still matches every txn.
  def suggested_payee(txns)
    normalized = txns.map { |t| PayeeRule.normalize(t.payee) }
    prefix = normalized.reduce do |a, b|
      a.chars.zip(b.chars).take_while { |x, y| x == y }.map(&:first).join
    end.to_s
    prefix = prefix[0...prefix.rindex(" ") || prefix.length] unless normalized.all? { |p| p == prefix }
    prefix.strip
  end

  def median_gap(dates)
    gaps = dates.each_cons(2).map { |a, b| (b - a).to_i }
    gaps.sort[gaps.size / 2]
  end

  # Skip payees already covered by an active rule on the same account.
  def covered?(rules, account_id, key)
    rules.any? do |r|
      r.account_id == account_id && key.include?(PayeeRule.normalize(r.payee))
    end
  end
end
