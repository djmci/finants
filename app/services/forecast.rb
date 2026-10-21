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
  attr_reader :accounts, :settlement_amounts

  # basis: :hybrid (rules + residual drift), :rules (scheduled items
  # only), :history (raw drift only — no rules, no masking).
  def initialize(accounts:, rules:, window_days: 90, basis: :hybrid)
    @accounts = Array(accounts)
    @basis = basis
    # :history → no rules; :rules → the full plan; :hybrid → only the
    # rules opted into the hybrid layer.
    @rules = case basis
             when :history then []
             when :rules   then rules
             else rules.select { |r| r.include_in_hybrid? }
             end
    @window_days = window_days
    # Settle rules need the target account projected even when it's
    # outside the scoped view — e.g. a bank→Amex payment in Cash view.
    @all_accounts = (@accounts + @rules.flat_map { |r| [ r.account, r.to_account ] }.compact).uniq
  end

  # {Account => [[Date, balance_cents], ...]} — every date in range.
  def series(range)
    deltas = occurrence_deltas(range)
    settles = settle_occurrences(range)
    if @basis == :rules
      # A settle target's balance is real data, not a plan — let real
      # drift drive its accrual, and skip the charge rules' deltas on
      # it (real history is the better measurement; both would double).
      target_ids = @rules.select(&:settle?).map(&:to_account_id)
      deltas = Hash.new(0).merge(deltas.reject { |(aid, _), _| target_ids.include?(aid) })
      disc = discretionary_daily(range).slice(*target_ids)
    else
      disc = discretionary_daily(range)
    end
    if @basis != :rules
      # Real income that no rule covers (reimbursements, refunds, misc)
      # drifts in too — masked exactly like spend.
      inflow = inflow_daily(range)
      disc = disc.merge(inflow) { |_, outflow, income| outflow + income }
    end
    if @basis == :history
      # Debt accrual is spend too: a card drifting more negative IS
      # money leaving, it just hasn't hit cash yet. Roll each
      # out-of-scope non-loan account's net rate onto the lead liquid.
      primary = @accounts.detect(&:liquid?)&.id
      if primary
        (Account.active - @all_accounts).reject(&:loan?).each do |a|
          rate = net_drift_for(a, range)
          disc[primary] = (disc[primary] || 0) + rate if rate != 0
        end
      end
    end
    bal = seed_balances(range)
    @settlement_amounts = {}
    installment_plans = {} # rule.id => { total:, remaining: } — split a settle into N equal payments
    points = @all_accounts.index_with { |a| [] }
    range.each do |d|
      @all_accounts.each { |a| bal[a.id] += deltas[[ a.id, d ]] + (disc[a.id] || 0) }
      (settles[d] || []).each do |rule|
        amt = -bal[rule.to_account_id]
        @settlement_amounts[[ rule.id, d ]] = amt
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

  # [[name, daily_cents (negative)]] for the visible scope — what the
  # "unexplained spend" actually is, broken down by real categories.
  def discretionary_breakdown(range)
    rows = discretionary_rows(range).select { |aid, _, _| @accounts.map(&:id).include?(aid) }
    names = Category.where(id: rows.map { |_, c, _| c }.compact.uniq).index_by(&:id)
    rows.group_by { |_, cid, _| cid }
        .map { |cid, rs| [ cid ? names[cid]&.display_name : "Uncategorised", rs.sum(&:last) / @window_days ] }
        .sort_by(&:last)
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
    discretionary_rows(range).group_by(&:first)
                             .transform_values { |rows| rows.sum(&:last) / @window_days }
  end

  # Net daily drift for one account — spend + income, transfers and
  # one-off categories excluded, just like the main drift.
  def net_drift_for(account, range)
    excluded_cats = Category.where(exclude_from_forecast: true).pluck(:id)
    from = range.begin - @window_days.days
    Transaction.where(account:, posted_on: from..(range.begin - 1), transfer_pair_id: nil)
               .where.not(category_id: excluded_cats)
               .sum(:amount_cents) / @window_days
  end

  # {account_id => +cents/day} — real income the rules don't cover.
  # Same exclusions as spend: transfers, one-off categories, rare
  # outliers, and rows a rule already models (in hybrid).
  def inflow_daily(range)
    excluded_cats = Category.where(exclude_from_forecast: true).pluck(:id)
    from = range.begin - @window_days.days
    # Only non-loan accounts produce income — a positive loan/card row
    # is debt plumbing (payment credit, refund), not money in.
    settle_targets = @rules.select(&:settle?).map(&:to_account_id)
    combos = Transaction.where(account: @all_accounts.reject(&:loan?), posted_on: from..(range.begin - 1),
                               transfer_pair_id: nil)
                        .where.not(account_id: settle_targets)
                        .where.not(category_id: excluded_cats)
                        .where("amount_cents > 0")
                        .group(:account_id, :payee, :amount_cents).count
    rules_by_account = @rules.select(&:active?).group_by(&:account_id)
    combos.group_by { |(account_id, _, _), _| account_id }.flat_map do |account_id, ac|
      samples = ac.flat_map { |(_, _, cents), n| [ cents ] * n }
      median = samples.sort[samples.size / 2] || 0
      cap = median * 4
      payee_hits = ac.group_by { |(_, payee, _), _| PayeeRule.detection_key(payee) }
                     .transform_values { |list| list.sum(&:last) }
      ac.filter_map do |(_, payee, cents), count|
        key = PayeeRule.detection_key(payee)
        next if payee_hits[key] <= 2 && cents > cap
        # Payee-only match for income — wage amounts wobble by cents,
        # an exact-amount check would leak the salary back into drift.
        matched = rules_by_account.fetch(account_id, []).any? do |r|
          rkey = PayeeRule.detection_key(r.payee)
          rkey.present? && key.include?(rkey)
        end
        [ account_id, cents * count ] unless matched
      end
    end.group_by(&:first).transform_values { |rows| rows.sum(&:last) / @window_days }
  end

  # [[account_id, category_id, total_cents]] — real 90d spend that
  # isn't transfers, rule-matched, a rare outlier, or a category the
  # user flagged as one-off (e.g. the Mexico trip — excluded so it
  # doesn't inflate the everyday-spend rate).
  def discretionary_rows(range)
    excluded_cats = Category.where(exclude_from_forecast: true).pluck(:id).to_set
    from = range.begin - @window_days.days
    combos = Transaction.where(account: @all_accounts, posted_on: from..(range.begin - 1),
                               transfer_pair_id: nil)
                        .where.not(category_id: excluded_cats)
                        .where("amount_cents < 0")
                        .group(:account_id, :category_id, :payee, :amount_cents).count
    rules_by_account = @rules.select(&:active?).group_by(&:account_id)
    combos.group_by { |(account_id, _, _, _), _| account_id }.flat_map do |account_id, ac|
      samples = ac.flat_map { |(_, _, _, cents), n| [ cents.abs ] * n }
      median = samples.sort[samples.size / 2] || 0
      cap = median * 4
      # Rare = the payee itself appears ≤2 times in the window, whatever
      # the amounts — a monthly variable bill is not a one-off.
      payee_hits = ac.group_by { |(_, _, payee, _), _| PayeeRule.detection_key(payee) }
                     .transform_values { |list| list.sum(&:last) }
      ac.filter_map do |(_, cid, payee, cents), count|
        key = PayeeRule.detection_key(payee)
        next if payee_hits[key] <= 2 && cents.abs > cap
        matched = rules_by_account.fetch(account_id, []).any? do |r|
          rkey = PayeeRule.detection_key(r.payee)
          rkey.present? && key.include?(rkey) &&
            (r.settle? || r.amount_cents.abs == cents.abs)
        end
        [ account_id, cid, cents * count ] unless matched
      end
    end
  end

  # {account_id => balance in cents at range.begin}
  # Settle uses the full computed balance — cards pay the statement,
  # not the post-payment accrual, so the owed figure includes the
  # persistent cycle float.
  def seed_balances(range)
    sums = Transaction.where(account: @all_accounts).where("posted_on < ?", range.begin)
                      .group(:account_id).sum(:amount_cents)
    @all_accounts.to_h { |a| [ a.id, a.opening_balance_cents + sums.fetch(a.id, 0) ] }
  end
end
