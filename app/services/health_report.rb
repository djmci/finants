# Household financial health — all numbers derived from real data:
# balances, imported history, and the recurring rules that model bills.
class HealthReport
  LIQUID_KINDS = %w[everyday savings cash].freeze
  DRIFT_DAYS = 90
  TREND_MONTHS = 6

  attr_reader :liquid, :rules, :projection

  def initialize(today: Date.current)
    @today = today
    @liquid = Account.active.select { |a| LIQUID_KINDS.include?(a.kind) }
    @rules = RecurringRule.active.includes(:account, :to_account, :category)
    @projection = Forecast.new(accounts: @liquid, rules: @rules)
                          .combined(@today..(@today + 12.months))
  end

  def cash_now = @liquid.sum(&:balance_cents)

  def min_point = @projection.min_by(&:last)
  def first_negative = @projection.find { |_d, c| c < 0 }&.first
  def projected_net_per_month = (@projection.last.last - @projection.first.last) / 12

  # Monthly committed in/out from rules (cents, positive magnitudes).
  # Committed = what leaves cash: expense rules on liquid accounts and
  # transfers out — charges on credit/loan accounts aren't cash, they
  # arrive via their settle payments (which we count instead).
  def monthly_income = @rules.select { |r| r.kind == "income" }.sum(&:monthly_cents)
  def monthly_committed
    liquid_ids = @liquid.map(&:id)
    @rules.select { |r| %w[expense transfer].include?(r.kind) && liquid_ids.include?(r.account_id) }
          .sum(&:monthly_cents) + settle_monthly
  end
  def coverage
    committed = monthly_committed
    committed.positive? ? (monthly_income / committed) : nil
  end

  # Settle rules pay whatever the card racked up — estimate a month's
  # payment from the actual payments seen over the drift window.
  def settle_monthly
    @rules.select(&:settle?).sum do |rule|
      key = PayeeRule.detection_key(rule.payee)
      spent = Transaction.where(account: rule.account, transfer_pair_id: nil)
                         .where(posted_on: (@today - DRIFT_DAYS.days)..@today)
                         .where("amount_cents < 0")
                         .select { |t| PayeeRule.detection_key(t.payee).include?(key) }
                         .sum(&:amount_cents)
      spent.abs / (DRIFT_DAYS / 30.0)
    end
  end

  # Last TREND_MONTHS calendar months of actual income vs spend on the
  # liquid accounts — the cash story, mirrors on loans/cards excluded.
  def monthly_trend
    first = @today.beginning_of_month << (TREND_MONTHS - 1)
    rows = Transaction.where(account: @liquid, transfer_pair_id: nil)
                      .where("posted_on >= ?", first)
                      .group("date_trunc('month', posted_on)")
                      .pluck(Arel.sql("date_trunc('month', posted_on)"),
                             Arel.sql("SUM(CASE WHEN amount_cents > 0 THEN amount_cents ELSE 0 END)"),
                             Arel.sql("SUM(CASE WHEN amount_cents < 0 THEN amount_cents ELSE 0 END)"))
    rows.sort_by(&:first).map do |month, income, spend|
      { month: month.to_date, income_cents: income, spend_cents: -spend, net_cents: income + spend }
    end
  end

  # Actual spend by category over the drift window — txns matched to a
  # rule count under the rule's category even if the row is untagged.
  def category_spend
    rules_by_account = @rules.group_by(&:account_id)
    txns = Transaction.where(transfer_pair_id: nil)
                      .where(posted_on: (@today - DRIFT_DAYS.days)..@today)
                      .where("amount_cents < 0")
                      .includes(:category)
    buckets = Hash.new(0)
    txns.each do |t|
      cat = t.category || matched_rule_category(t, rules_by_account)
      buckets[cat&.display_name || "Uncategorised"] += t.amount_cents.abs
    end
    months = DRIFT_DAYS / 30.0
    buckets.map { |name, cents| [ name, cents / months ] }.sort_by { |_, c| -c }
  end

  private

  def matched_rule_category(txn, rules_by_account)
    RecurringRule.match_for(account: txn.account, payee: txn.payee, amount_cents: txn.amount_cents)
                 &.category
  end
end
