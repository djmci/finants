# Pure projection engine — all inputs bulk-loaded by the caller.
#
# For each account, a projected daily balance over `range`:
#   balance(d) = opening + Σ actual txns before range.start
#              + recurring-rule occurrences on/before d
#              + settle rules (dynamic: amount = −target's balance)
#              + discretionary daily estimate
#
# Discretionary estimate v1: trailing `window_days` mean daily outflow
# per account, excluding transfer pairs and anything matching an active
# rule — the rules already model that spend, so it can't double-count.
class Forecast
  attr_reader :accounts

  def initialize(accounts:, rules:, window_days: 90)
    @accounts = Array(accounts)
    @rules = rules
    @window_days = window_days
    # Settle rules need the target account projected even when it's
    # outside the scoped view — e.g. a bank→Amex payment in Cash view.
    @all_accounts = (@accounts + @rules.flat_map { |r| [ r.account, r.to_account ] }.compact).uniq
  end

  # {Account => [[Date, balance_cents], ...]} — every date in range.
  def series(range)
    deltas = occurrence_deltas(range)
    settles = settle_occurrences(range)
    disc = discretionary_daily(range)
    bal = seed_balances(range)
    points = @all_accounts.index_with { |a| [] }
    range.each do |d|
      @all_accounts.each { |a| bal[a.id] += deltas[[ a.id, d ]] + (disc[a.id] || 0) }
      (settles[d] || []).each do |rule|
        amt = -bal[rule.to_account_id]
        bal[rule.to_account_id] += amt
        bal[rule.account_id] -= amt
      end
      @all_accounts.each { |a| points[a] << [ d, bal[a.id] ] }
    end
    @accounts.to_h { |a| [ a, points[a] ] }
  end

  # Household combined: sum of all series, same dates.
  def combined(range)
    per_account = series(range)
    dates = range.to_a
    dates.each_index.map do |i|
      [ dates[i], per_account.values.sum { |pts| pts[i][1] } ]
    end
  end

  # [date, cents] of the lowest point in the combined series.
  def minimum(range)
    combined(range).min_by(&:last)
  end

  private

  # Static deltas — settle rules are evaluated dynamically in the walk.
  # {[account_id, date] => delta_cents}
  def occurrence_deltas(range)
    deltas = Hash.new(0)
    Recurring.occurrences_for(@rules, range).each do |o|
      rule = o[:rule]
      next if rule.settle?
      if rule.kind == "transfer"
        deltas[[ rule.account_id, o[:on] ]] -= rule.amount_cents.abs
        deltas[[ rule.to_account_id, o[:on] ]] += rule.amount_cents.abs
      else
        deltas[[ rule.account_id, o[:on] ]] += rule.signed_amount_cents
      end
    end
    deltas
  end

  # {date => [rule]} for settle rules.
  def settle_occurrences(range)
    Recurring.occurrences_for(@rules.select(&:settle?), range)
      .group_by { |o| o[:on] }.transform_values { |os| os.map { |o| o[:rule] } }
  end

  # {account_id => daily expense cents (negative)}
  # Excludes transfer pairs and anything matching an active rule —
  # including rows not yet linked via recurring_rule_id (e.g. imported
  # mortgage payments) — so they aren't double-counted by the rules.
  def discretionary_daily(range)
    from = range.begin - @window_days.days
    combos = Transaction.where(account: @all_accounts, posted_on: from..(range.begin - 1),
                               transfer_pair_id: nil)
                        .where("amount_cents < 0")
                        .group(:account_id, :payee, :amount_cents).count
    rules_by_account = @rules.select(&:active?).group_by(&:account_id)
    totals = Hash.new(0)
    combos.each do |(account_id, payee, cents), count|
      key = PayeeRule.detection_key(payee)
      matched = rules_by_account.fetch(account_id, []).any? do |r|
        rkey = PayeeRule.detection_key(r.payee)
        rkey.present? && key.include?(rkey) &&
          (r.settle? || r.amount_cents.abs == cents.abs)
      end
      totals[account_id] += cents * count unless matched
    end
    totals.transform_values { |sum| sum / @window_days }
  end

  # {account_id => balance in cents at range.begin}
  def seed_balances(range)
    sums = Transaction.where(account: @all_accounts).where("posted_on < ?", range.begin)
                      .group(:account_id).sum(:amount_cents)
    @all_accounts.to_h { |a| [ a.id, a.opening_balance_cents + sums.fetch(a.id, 0) ] }
  end
end
