# Pure projection engine — all inputs bulk-loaded by the caller.
#
# For each account, a projected daily balance over `range`:
#   balance(d) = opening + Σ actual txns before range.start
#              + recurring-rule occurrences on/before d
#              + discretionary daily estimate
#
# Discretionary estimate v1: trailing `window_days` mean daily outflow
# per account, excluding transfer pairs and rule-linked txns (they're
# covered by the rules).
class Forecast
  attr_reader :accounts

  def initialize(accounts:, rules:, window_days: 90)
    @accounts = Array(accounts)
    @rules = rules
    @window_days = window_days
  end

  # {Account => [[Date, balance_cents], ...]} — every date in range.
  def series(range)
    deltas = occurrence_deltas(range)
    disc = discretionary_daily(range)
    seeds = seed_balances(range)
    @accounts.to_h do |account|
      bal = seeds[account.id]
      daily = disc[account.id] || 0
      points = range.map do |d|
        bal += deltas[[ account.id, d ]] + daily
        [ d, bal ]
      end
      [ account, points ]
    end
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

  # {[account_id, date] => delta_cents}
  def occurrence_deltas(range)
    deltas = Hash.new(0)
    Recurring.occurrences_for(@rules, range).each do |o|
      rule = o[:rule]
      if rule.kind == "transfer"
        deltas[[ rule.account_id, o[:on] ]] -= rule.amount_cents.abs
        deltas[[ rule.to_account_id, o[:on] ]] += rule.amount_cents.abs
      else
        deltas[[ rule.account_id, o[:on] ]] += rule.signed_amount_cents
      end
    end
    deltas
  end

  # {account_id => daily expense cents (negative)}
  def discretionary_daily(range)
    from = range.begin - @window_days.days
    Transaction.where(account: @accounts, posted_on: from..(range.begin - 1),
                      recurring_rule_id: nil, transfer_pair_id: nil)
               .where("amount_cents < 0")
               .group(:account_id).sum(:amount_cents)
               .transform_values { |sum| sum / @window_days }
  end

  # {account_id => balance in cents at range.begin}
  def seed_balances(range)
    sums = Transaction.where(account: @accounts).where("posted_on < ?", range.begin)
                      .group(:account_id).sum(:amount_cents)
    @accounts.to_h { |a| [ a.id, a.opening_balance_cents + sums.fetch(a.id, 0) ] }
  end
end
