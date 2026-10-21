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
  # Settle payments are excluded: paying the card isn't spend — the
  # card's charges already count under their real categories.
  # Loans excluded: loan-account interest is an accrual entry — it
  # lengthens the repayment tail, it doesn't move cash. Card charges
  # still count — that's where the spend happens.
  def category_spend
    spend_accounts = Account.active.select { |a| a.kind != "loan" }
    txns = Transaction.where(account: spend_accounts, transfer_pair_id: nil)
                      .where(posted_on: (@today - DRIFT_DAYS.days)..@today)
                      .includes(:category)
    buckets = Hash.new(0)
    settle_targets = @rules.select(&:settle?).map(&:to_account_id)
    txns.each do |t|
      # Credits on a settle target are payment receipts — they mirror
      # the excluded bank-side leg, they'd only net the charges away.
      next if t.amount_cents.positive? && settle_targets.include?(t.account_id)
      rule = RecurringRule.match_for(account: t.account, payee: t.payee, amount_cents: t.amount_cents)
      next if rule&.settle?
      cat = t.category || rule&.category
      # Signed sum: a reimbursement tagged with the spend's category
      # nets the category down to its true cost.
      buckets[cat&.display_name || "Uncategorised"] -= t.amount_cents
    end
    # Card spend the charge txns don't explain: real settle payments
    # minus tracked charges on the card. Until statements are imported
    # this is the whole payment; after, it's the unexplained residual.
    @rules.select(&:settle?).each do |rule|
      key = PayeeRule.detection_key(rule.payee)
      window = (@today - DRIFT_DAYS.days)..@today
      paid = Transaction.where(account: rule.account, transfer_pair_id: nil)
                        .where(posted_on: window).where("amount_cents < 0")
                        .select { |t| PayeeRule.detection_key(t.payee).include?(key) }
                        .sum { |t| t.amount_cents.abs }
      charged = Transaction.where(account: rule.to_account, transfer_pair_id: nil)
                           .where(posted_on: window).where("amount_cents < 0")
                           .sum(:amount_cents).abs
      residual = paid - charged
      buckets["Card settlement (unallocated)"] += residual if residual.positive?
    end
    buckets.delete_if { |_, cents| cents <= 0 }
    months = DRIFT_DAYS / 30.0
    buckets.map { |name, cents| [ name, cents / months ] }.sort_by { |_, c| -c }
  end
end
