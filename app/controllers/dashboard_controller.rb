class DashboardController < ApplicationController
  allow_unauthenticated_access only: :index

  HISTORY_DAYS = 90

  # Quacks like a RecurringRule for the calendar — a day's projected
  # category spend is drift, not a plan.
  ProjectedItem = Struct.new(:payee, :kind, :amount_cents, :account, keyword_init: true) do
    def settle? = false
    def to_account = nil
    def signed_amount_cents = kind == "expense" ? -amount_cents.abs : amount_cents.abs
  end
  HORIZONS = { "Next month" => 1.month, "Next quarter" => 3.months, "Next year" => 12.months }.freeze

  def index
    return render :landing unless authenticated?
    @accounts = Account.active.includes(:owner).order(:name)
    @liquid = @accounts.select { |a| a.liquid? }
    @uncategorised_count = Transaction.uncategorised.count
    rules = RecurringRule.live.active.includes(:account, :category, :to_account)

    @months = (params[:months].presence || 6).to_i.clamp(1, 36)
    @basis = %w[hybrid rules history].include?(params[:basis]) ? params[:basis].to_sym : :hybrid
    @scoped_account = @accounts.detect { |a| a.id.to_s == params[:account] }
    scope = @scoped_account ? [ @scoped_account ] : @liquid
    # Tracked averages a full year of history — a 90-day window is too
    # easily skewed by one-off-heavy quarters (e.g. the Mexico trip).
    forecast = Forecast.new(accounts: scope, rules: rules, basis: @basis,
                          window_days: @basis == :history ? 365 : 90)
    full = forecast.combined(Date.current..(Date.current + [ @months, 12 ].max.months))
    @settle_amounts = forecast.settlement_amounts || {}
    @history = balance_history(scope)
    # The projection can start before today — it peels off the actuals
    # where the last import ran out. Clamp it to the chart window.
    @projection = full.select { |d, _| d >= @history.first.first && d <= Date.current + @months.months }
    fwd = @projection.select { |d, _| d >= Date.current }

    # Scenario overlay — a second dashed line from the copied rule set.
    @scenarios = Scenario.order(:name)
    @scenario = @scenarios.detect { |s| s.id.to_s == params[:scenario] }
    if @scenario
      srules = @scenario.recurring_rules.active.includes(:account, :category, :to_account)
      @scenario_projection = Forecast.new(accounts: scope, rules: srules, basis: @basis)
                                     .combined(Date.current..(Date.current + @months.months))
                                     .select { |d, _| d >= @history.first.first }
    end
    @floor = fwd.min_by(&:last)
    @net_flow = ongoing_rate(fwd)
    @drift_categories = forecast.discretionary_breakdown(Date.current..(Date.current + 1.day))

    # Calendar — rule occurrences plus a weekly projected-spend line on
    # each Monday (the drift no rule covers, rolled up by category —
    # expandable in the cell). Only from today forward: past days are
    # actuals, not projections.
    @cal_month = (Date.strptime(params[:cal_month].to_s, "%Y-%m") rescue Date.current).beginning_of_month
    # Generate from today, not the month's first — a once-rule due
    # earlier lands "now" once, instead of re-landing on the 1st of
    # every month the calendar pages to.
    range = [ @cal_month, Date.current ].min..@cal_month.end_of_month
    @cal_days = Recurring.occurrences_for(rules, range).group_by { |o| o[:on] }
    weekly = @drift_categories.map { |name, cents| [ name, cents * 7 ] }
    weekly_total = weekly.sum(&:last)
    if weekly_total != 0
      item = ProjectedItem.new(payee: "Weekly spend", amount_cents: weekly_total.abs,
                               kind: weekly_total.negative? ? "expense" : "income", account: nil)
      monday = range.begin
      monday += 1 until monday.wday == 1 || monday > range.end
      while monday <= range.end
        # This week's remainder lands today; future weeks on their Monday.
        d = [ monday, Date.current ].max
        (@cal_days[d] ||= []) << { rule: item, on: d, projected: true, breakdown: weekly } if d <= range.end
        monday += 7
      end
    end

    # Health + alerts always track the liquid cash position, whatever
    # scope the chart is showing — a card/loan balance is negative by
    # nature, not a breach.
    cash = Forecast.new(accounts: @liquid, rules: rules, basis: @basis,
                        window_days: @basis == :history ? 365 : 90)
                   .combined(Date.current..(Date.current + 12.months))
                   .select { |d, _| d >= Date.current }
    @cash_now = cash.first.last
    @health = HORIZONS.to_h { |name, span| [ name, checkpoint(cash, Date.current + span) ] }
    monitor = CashflowMonitor.new(warn: Setting.alert_warn_cents, critical: Setting.alert_critical_cents)
    @breaches = monitor.breaches(cash)
    @smoothing = SmoothingSuggestions.new(points: cash, rules: rules,
                                          warn_cents: Setting.alert_warn_cents).call
    @health.each_value { |h| h[:severity] = monitor.severity_of(cash.select { |d, _| d <= h[:date] }) }
    @alert_warn = Setting.alert_warn_cents / 100.0
    @alert_critical = Setting.alert_critical_cents / 100.0
  end

  private

  # Least-squares slope over the back 60% of the projection — the first
  # chunk carries one-time stock events (e.g. the card's debt payoff)
  # that would smear a whole-span fit into the "ongoing" rate.
  def ongoing_rate(points)
    return 0 if points.size < 2
    tail = points.drop((points.size * 0.4).floor)
    xs = (0...tail.size).to_a
    ys = tail.map(&:last)
    n = xs.size
    slope = (n * xs.zip(ys).sum { |x, y| x * y } - xs.sum * ys.sum) /
            (n * xs.sum { |x| x * x } - xs.sum**2).to_f
    (slope * 30).round
  end

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
