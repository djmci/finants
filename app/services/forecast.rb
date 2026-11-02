# Pure projection engine — all inputs bulk-loaded by the caller.
#
# Every walked account replays real transactions through the last day
# its data covers (its data-as-of), then forecasts from the day after:
#   balance(d) = real txns on d — wherever actuals exist, including
#                strays dated into the future
#              + recurring-rule occurrences on d (only once d is past
#                the account's data-as-of — actuals are the truth)
#              + settle rules (dynamic: amount = −target's balance)
#              + discretionary daily estimate
#
# The returned series can start before `range.begin`: the walk begins
# at the earliest day any account ran out of actuals, so a bill due
# after the last import still projects instead of falling into the
# gap between history and today. Callers after "from now" numbers
# should slice on d >= range.begin.
#
# Discretionary estimate v1: trailing `window_days` mean daily outflow
# per account, excluding transfer pairs and anything matching an active
# rule — the rules already model that spend, so it can't double-count.
# The window ends where the account's data does, not at range.begin.
class Forecast
  # Days past a due date a real posting can still land — weekend
  # slips, bank processing lag. An occurrence due within this window
  # of the data edge is pending: projected unless a matching txn
  # exists. Older unposted dates are settled — the data is the truth.
  PENDING_DAYS = 4

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

  # {Account => [[Date, balance_cents], ...]} — every date in the walk,
  # which may begin before range.begin (see class comment).
  def series(range)
    as_of = data_as_of(range.begin)
    # The walk also reaches back into the lag window — the last days
    # of "data" are exactly the ones a pending payment may not have
    # hit yet, and their occurrences must still be evaluated.
    oldest = as_of.values.min
    walk_start = [ range.begin, (oldest ? oldest - PENDING_DAYS + 1 : range.begin) ].min
    walk = walk_start..range.end
    actual, txns_by_day = actual_index(walk)
    # :rules basis trusts real drift on settle targets — their charge
    # rules stay out of the walk (both would double-count the spend).
    skip_accts = @basis == :rules ? @rules.select(&:settle?).map(&:to_account_id) : []
    by_day = occurrence_index(walk, as_of, txns_by_day, skip_accts)
    settles = settle_index(walk, as_of, txns_by_day)
    if @basis == :rules
      disc = discretionary_daily(as_of).slice(*skip_accts)
    else
      disc = discretionary_daily(as_of)
    end
    if @basis != :rules
      # Real income that no rule covers (reimbursements, refunds, misc)
      # drifts in too — masked exactly like spend.
      inflow = inflow_daily(as_of)
      disc = disc.merge(inflow) { |_, outflow, income| outflow + income }
    end
    if @basis == :history
      # Debt accrual is spend too: a card drifting more negative IS
      # money leaving, it just hasn't hit cash yet. Roll each
      # out-of-scope non-loan account's net rate onto the lead liquid.
      primary = @accounts.detect(&:liquid?)&.id
      if primary
        (Account.active - @all_accounts).reject(&:loan?).each do |a|
          rate = net_drift_for(a, as_of)
          disc[primary] = (disc[primary] || 0) + rate if rate != 0
        end
      end
    end
    bal = seed_balances(walk_start)
    @settlement_amounts = {}
    epoch = Date.new(1) # as_of floor — no data means "always forecast"
    points = @all_accounts.index_with { |a| [] }
    walk.each do |d|
      @all_accounts.each do |a|
        bal[a.id] += actual[[ a.id, d ]]
        bal[a.id] += (disc[a.id] || 0) if d > (as_of[a.id] || epoch)
      end
      (by_day[d] || []).each do |o|
        rule = o[:rule]
        if rule.kind == "transfer"
          bal[rule.account_id] -= rule.amount_cents.abs if leg_live?(rule, d, rule.account_id, :out, as_of, txns_by_day)
          bal[rule.to_account_id] += rule.amount_cents.abs if leg_live?(rule, d, rule.to_account_id, :in, as_of, txns_by_day)
        elsif leg_live?(rule, d, rule.account_id, rule.kind == "expense" ? :out : :in, as_of, txns_by_day)
          bal[rule.account_id] += rule.signed_amount_cents
        end
      end
      (settles[d] || []).each do |rule|
        next unless leg_live?(rule, d, rule.account_id, :out, as_of, txns_by_day)
        amt = -bal[rule.to_account_id]
        @settlement_amounts[[ rule.id, d ]] = amt
        bal[rule.account_id] -= amt
        # The card side gets its projected credit only past its own
        # data — covered actuals decide whether it really landed.
        bal[rule.to_account_id] += amt if d > (as_of[rule.to_account_id] || epoch)
      end
      @all_accounts.each { |a| points[a] << [ d, bal[a.id] ] }
    end
    @accounts.to_h { |a| [ a, points[a] ] }
  end

  # Household combined: sum of all series, same dates. Dates come from
  # the walk itself — it may start before range.begin.
  def combined(range)
    per_account = series(range)
    dates = per_account.values.first&.map(&:first) || []
    dates.each_index.map do |i|
      [ dates[i], per_account.values.sum { |pts| pts[i][1] } ]
    end
  end

  # [date, cents] of the lowest point in the combined series, looking
  # forward from range.begin — a dip in the stale tail already happened.
  def minimum(range)
    combined(range).select { |d, _| d >= range.begin }.min_by(&:last)
  end

  # [[name, daily_cents (negative)]] for the visible scope — what the
  # "unexplained spend" actually is, broken down by real categories.
  def discretionary_breakdown(range)
    rows = discretionary_rows(data_as_of(range.begin))
           .select { |aid, _, _| @accounts.map(&:id).include?(aid) }
    names = Category.where(id: rows.map { |_, c, _| c }.compact.uniq).index_by(&:id)
    rows.group_by { |_, cid, _| cid }
        .map { |cid, rs| [ cid ? names[cid]&.display_name : "Uncategorised", rs.sum(&:last) / @window_days ] }
        .sort_by(&:last)
  end

  private

  # {account_id => Date} — the last day each account's actuals cover,
  # capped at the projection start (a stray future-dated txn doesn't
  # mean the feed runs that far).
  def data_as_of(upto)
    Transaction.where(account: @all_accounts)
               .where("posted_on <= ?", upto)
               .group(:account_id).maximum(:posted_on)
  end

  # [{[account_id, date] => cents}, {[account_id, date] => [txn, ...]}]
  # Real txns inside the walk (plus POSTING_LAG slack for the pending
  # check): the daily sums replay verbatim — transfer pairs included —
  # and the row index answers "did this occurrence actually post?".
  def actual_index(walk)
    sums = Hash.new(0)
    by_day = Hash.new { |h, k| h[k] = [] }
    Transaction.where(account: @all_accounts,
                      posted_on: (walk.begin - PENDING_DAYS)..walk.end)
               .pluck(:account_id, :posted_on, :payee, :amount_cents, :recurring_rule_id)
               .each do |account_id, d, payee, cents, rule_id|
      by_day[[ account_id, d ]] << { cents:, rule_id:, key: PayeeRule.detection_key(payee) }
      sums[[ account_id, d ]] += cents
    end
    [ sums, by_day ]
  end

  # Did this occurrence's leg actually post? Match a real txn on the
  # account within posting lag of the due date — an explicit rule link
  # always counts; otherwise payee-key + amount like match_for (settle
  # legs vary, transfers carry counterparty text so amount is the key).
  def posted?(rule, on, account_id, direction, by_day)
    rkey = rule_key(rule)
    want_neg = direction == :out
    # A posting can land a couple of days early, or several late;
    # kept narrow so weekly cadences can't cross-match.
    ((on - 2)..(on + PENDING_DAYS)).any? do |d|
      by_day[[ account_id, d ]].any? do |t|
        next true if t[:rule_id] == rule.id
        next false unless (t[:cents] < 0) == want_neg
        case rule.kind
        when "settle"   then rkey.present? && t[:key].include?(rkey)
        when "transfer" then t[:cents].abs == rule.amount_cents.abs
        else rkey.present? && t[:key].include?(rkey) && t[:cents].abs == rule.amount_cents.abs
        end
      end
    end
  end

  # Should this occurrence's leg apply on day `on` for `account_id`?
  # Past the data edge always; in the lag window only if it hasn't
  # really posted; deep inside covered actuals never — the data is
  # the truth about what happened.
  def leg_live?(rule, on, account_id, direction, as_of, by_day)
    cutoff = as_of[account_id]
    return true unless cutoff
    return true if on > cutoff
    return false if on <= cutoff - PENDING_DAYS
    !posted?(rule, on, account_id, direction, by_day)
  end

  # {account_id => [rule]} — the rules that explain real spend for
  # drift masking. Always the LIVE set, basis-filtered the same way
  # @rules was built: actuals only ever match live rules (match_for
  # is live.active), so a scenario's edited amounts must not unmask
  # the real spend they model — the rule would fire AND the actuals
  # would leak into drift, double-counting the bill.
  def mask_rules_by_account
    live = case @basis
           when :history then []
           when :rules   then RecurringRule.live.active
           else RecurringRule.live.active.select(&:include_in_hybrid?)
           end
    live.group_by(&:account_id)
  end

  # The effective date for a once-rule: nil if it already posted (the
  # actual is in the data), otherwise its due date — except an overdue
  # one, which stays pending and lands the day the account's data ends.
  def once_landing(rule, direction, as_of, by_day)
    return nil if posted?(rule, rule.start_on, rule.account_id, direction, by_day)
    cutoff = as_of[rule.account_id]
    # Ancient-overdue lands the day the data ends; a pending-zone or
    # future due date keeps its date, like a recurring occurrence.
    on = cutoff && rule.start_on <= cutoff - PENDING_DAYS ? cutoff + 1 : rule.start_on
    on unless rule.end_on && on > rule.end_on
  end

  # {date => [{rule:, on:}]} — non-settle occurrences over the walk.
  # Once rules are planned items, not schedules: an overdue one stays
  # pending until it posts, it never just evaporates.
  def occurrence_index(walk, as_of, by_day, skip_account_ids)
    Hash.new { |h, k| h[k] = [] }.tap do |by_day|
      Recurring.occurrences_for(@rules.reject(&:settle?), walk).each do |o|
        rule = o[:rule]
        next if skip_account_ids.include?(rule.account_id)
        on = o[:on]
        if rule.frequency == "once"
          dir = rule.kind == "income" ? :in : :out
          on = once_landing(rule, dir, as_of, by_day)
          next if on.nil? || on > walk.end
          on = [ on, walk.begin ].max
        end
        by_day[on] << o.merge(on:)
      end
    end
  end

  # {date => [rule]} for settle rules — same once-rule pending logic.
  def settle_index(walk, as_of, by_day)
    Recurring.occurrences_for(@rules.select(&:settle?), walk)
      .each_with_object(Hash.new { |h, k| h[k] = [] }) do |o, h|
        on = o[:on]
        if o[:rule].frequency == "once"
          on = once_landing(o[:rule], :out, as_of, by_day)
          next if on.nil? || on > walk.end
          on = [ on, walk.begin ].max
        end
        h[on] << o[:rule]
      end
  end

  def rule_key(rule)
    (@rule_keys ||= {})[rule.id] ||= PayeeRule.detection_key(rule.payee)
  end

  # Trailing window of real data for drift measurement — ends where
  # the account's actuals do, not at the projection start, so a stale
  # feed doesn't dilute the daily rate with empty days.
  def drift_window(account, as_of)
    upto = as_of[account.id]
    upto && ((upto - @window_days + 1)..upto)
  end

  # {account_id => daily expense cents (negative)}
  # Excludes transfer pairs and anything matching an active rule —
  # including rows not yet linked via recurring_rule_id (e.g. imported
  # mortgage payments) — so they aren't double-counted by the rules.
  def discretionary_daily(as_of)
    discretionary_rows(as_of).group_by(&:first)
                             .transform_values { |rows| rows.sum(&:last) / @window_days }
  end

  # Net daily drift for one account — spend + income, transfers and
  # one-off categories excluded, just like the main drift.
  def net_drift_for(account, as_of)
    window = drift_window(account, as_of)
    return 0 unless window
    excluded_cats = Category.where(exclude_from_forecast: true).pluck(:id)
    Transaction.where(account:, posted_on: window, transfer_pair_id: nil)
               .where.not(category_id: excluded_cats)
               .sum(:amount_cents) / @window_days
  end

  # {account_id => +cents/day} — real income the rules don't cover.
  # Same exclusions as spend: transfers, one-off categories, rare
  # outliers, and rows a rule already models (in hybrid).
  def inflow_daily(as_of)
    excluded_cats = Category.where(exclude_from_forecast: true).pluck(:id)
    # Only non-loan accounts produce income — a positive loan/card row
    # is debt plumbing (payment credit, refund), not money in.
    settle_targets = @rules.select(&:settle?).map(&:to_account_id)
    combos = @all_accounts.reject { |a| a.loan? || settle_targets.include?(a.id) }
                          .each_with_object({}) do |a, h|
      window = drift_window(a, as_of)
      next unless window
      h.merge! Transaction.where(account: a, posted_on: window, transfer_pair_id: nil)
                          .where.not(category_id: excluded_cats)
                          .where("amount_cents > 0")
                          .group(:payee, :amount_cents).count
                          .transform_keys { |(payee, cents)| [ a.id, payee, cents ] }
    end
    rules_by_account = mask_rules_by_account
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
  def discretionary_rows(as_of)
    excluded_cats = Category.where(exclude_from_forecast: true).pluck(:id).to_set
    combos = @all_accounts.each_with_object({}) do |a, h|
      window = drift_window(a, as_of)
      next unless window
      h.merge! Transaction.where(account: a, posted_on: window, transfer_pair_id: nil)
                          .where.not(category_id: excluded_cats)
                          .where("amount_cents < 0")
                          .group(:category_id, :payee, :amount_cents).count
                          .transform_keys { |(cid, payee, cents)| [ a.id, cid, payee, cents ] }
    end
    rules_by_account = mask_rules_by_account
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

  # {account_id => balance in cents just before `upto`}
  # Settle uses the full computed balance — cards pay the statement,
  # not the post-payment accrual, so the owed figure includes the
  # persistent cycle float.
  def seed_balances(upto)
    sums = Transaction.where(account: @all_accounts).where("posted_on < ?", upto)
                      .group(:account_id).sum(:amount_cents)
    @all_accounts.to_h { |a| [ a.id, a.opening_balance_cents + sums.fetch(a.id, 0) ] }
  end
end
