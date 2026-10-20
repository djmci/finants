class DashboardController < ApplicationController
  HISTORY_DAYS = 90
  LIQUID_KINDS = %w[everyday savings cash].freeze
  HORIZONS = { "Now" => 1.month, "Near" => 3.months, "Far" => 12.months }.freeze

  def index
    @accounts = Account.active.includes(:owner).order(:name)
    @liquid = @accounts.select { |a| LIQUID_KINDS.include?(a.kind) }
    @uncategorised_count = Transaction.uncategorised.count
    rules = RecurringRule.active.includes(:account, :category, :to_account)
    @upcoming = Recurring.occurrences_for(rules, Date.current..(Date.current + 30))

    @months = (params[:months].presence || 6).to_i.clamp(1, 24)
    @scoped_account = @liquid.detect { |a| a.id.to_s == params[:account] }
    scope = @scoped_account ? [ @scoped_account ] : @liquid
    forecast = Forecast.new(accounts: scope, rules: rules)
    full = forecast.combined(Date.current..(Date.current + [ @months, 12 ].max.months))
    @projection = full.take_while { |d, _| d <= Date.current + @months.months }
    @history = balance_history(scope)
    @health = HORIZONS.to_h { |name, span| [ name, checkpoint(full, Date.current + span) ] }
    @floor = @projection.min_by(&:last)
    @net_flow = @projection.size > 1 ? (@projection.last.last - @projection.first.last) / @months : 0

    monitor = CashflowMonitor.new(warn: Setting.alert_warn_cents, critical: Setting.alert_critical_cents)
    @breaches = monitor.breaches(full)
    @health.each_value { |h| h[:severity] = monitor.severity_of(full.select { |d, _| d <= h[:date] }) }
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
