class DashboardController < ApplicationController
  HISTORY_DAYS = 90
  HORIZONS = { "Next month" => 1.month, "Next quarter" => 3.months, "Next year" => 12.months }.freeze

  def index
    @accounts = Account.active.includes(:owner).order(:name)
    @liquid = @accounts.select { |a| a.liquid? }
    @uncategorised_count = Transaction.uncategorised.count
    rules = RecurringRule.active.includes(:account, :category, :to_account)
    @upcoming = Recurring.occurrences_for(rules, Date.current..(Date.current + 30))

    @months = (params[:months].presence || 6).to_i.clamp(1, 24)
    @basis = %w[hybrid rules history].include?(params[:basis]) ? params[:basis].to_sym : :hybrid
    @scoped_account = @accounts.detect { |a| a.id.to_s == params[:account] }
    scope = @scoped_account ? [ @scoped_account ] : @liquid
    forecast = Forecast.new(accounts: scope, rules: rules, basis: @basis)
    full = forecast.combined(Date.current..(Date.current + [ @months, 12 ].max.months))
    @projection = full.take_while { |d, _| d <= Date.current + @months.months }
    @history = balance_history(scope)
    @floor = @projection.min_by(&:last)
    @net_flow = @projection.size > 1 ? (@projection.last.last - @projection.first.last) / @months : 0
    @drift_categories = forecast.discretionary_breakdown(Date.current..(Date.current + 1.day))

    # Health + alerts always track the liquid cash position, whatever
    # scope the chart is showing — a card/loan balance is negative by
    # nature, not a breach.
    cash = Forecast.new(accounts: @liquid, rules: rules, basis: @basis)
                   .combined(Date.current..(Date.current + 12.months))
    @cash_now = cash.first.last
    @health = HORIZONS.to_h { |name, span| [ name, checkpoint(cash, Date.current + span) ] }
    monitor = CashflowMonitor.new(warn: Setting.alert_warn_cents, critical: Setting.alert_critical_cents)
    @breaches = monitor.breaches(cash)
    @health.each_value { |h| h[:severity] = monitor.severity_of(cash.select { |d, _| d <= h[:date] }) }
    @alert_warn = Setting.alert_warn_cents / 100.0
    @alert_critical = Setting.alert_critical_cents / 100.0
  end

  private

  # Projected balance at the horizon date, plus delta from today.
  def checkpoint(points, upto)
    window = points.select { |d, _| d <= upto }
    { date: window.last.first, end_cents: window.last.last,
      delta: window.last.last - points.first.last }
  end

  # Actual combined daily balance for the trailing HISTORY_DAYS.
  def balance_history(accounts)
    range = (Date.current - HISTORY_DAYS.days)..Date.current
    sums = Transaction.where(account: accounts, posted_on: range)
                      .group(:posted_on).sum(:amount_cents)
    seed = accounts.sum(&:opening_balance_cents) +
           Transaction.where(account: accounts).where("posted_on < ?", range.begin).sum(:amount_cents)
    bal = seed
    range.map { |d| bal += sums[d] || 0; [ d, bal ] }
  end
end
