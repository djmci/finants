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
    # Custom range overrides the preset horizon: today (or `from`) → `to`.
    @from = (Date.parse(params[:from].to_s) rescue nil)
    @to = (Date.parse(params[:to].to_s) rescue nil)
    @end_date = @to || Date.current + @months.months
    @scoped_account = @accounts.detect { |a| a.id.to_s == params[:account] }
    scope = @scoped_account ? [ @scoped_account ] : @liquid
    forecast = Forecast.new(accounts: scope, rules: rules, basis: :hybrid, window_days: 90)
    full = forecast.combined(Date.current..[ @end_date, Date.current + 12.months ].max)
    @settle_amounts = forecast.settlement_amounts || {}
    # Archived accounts stay in the history — a replaced account's real
    # balance is still what the household held before the handover.
    # `from` stretches the window: a custom range can reach back past
    # the default 90 days.
    @history = balance_history(@scoped_account ? scope : Account.where(kind: Account::LIQUID), since: @from)
    @history = @history.select { |d, _| (!@from || d >= @from) && d <= @end_date }
    # The projection can start before today — it peels off the actuals
    # where the last import ran out. Clamp it to the chart window.
    floor_d = @history.first&.first || @from || Date.new(1)
    @projection = full.select { |d, _| d >= floor_d && d <= @end_date }
    @projection = @projection.select { |d, _| d >= @from } if @from
    # The lag-window walk still prices pending items into the balance —
    # the line just isn't drawn back into the past.
    @projection = @projection.select { |d, _| d >= Date.current }
    fwd = @projection.select { |d, _| d >= Date.current }

    # Scenario overlay — a second dashed line from the copied rule set.
    @scenarios = Scenario.order(:name)
    @scenario = @scenarios.detect { |s| s.id.to_s == params[:scenario] }
    if @scenario
      srules = @scenario.recurring_rules.active.includes(:account, :category, :to_account)
      @scenario_projection = Forecast.new(accounts: scope, rules: srules, basis: :hybrid, window_days: 90)
                                     .combined(Date.current..@end_date)
                                     .select { |d, _| d >= floor_d }
      @scenario_projection = @scenario_projection.select { |d, _| d >= @from } if @from
      @scenario_projection = @scenario_projection.select { |d, _| d >= Date.current }
    end
    # Stats track whatever the window shows — projected forward, or the
    # real history when the range is entirely in the past.
    @floor = (fwd.presence || @history).min_by(&:last)
    @net_flow = ongoing_rate(fwd.presence || @history)
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
    cash = Forecast.new(accounts: @liquid, rules: rules, basis: :hybrid, window_days: 90)
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

  # Actual combined daily balance for the trailing window (90 days, or
  # back to `since` when a custom range reaches further). Per-account
  # so opened_on works — an account contributes nothing until it
  # exists, then its opening balance starts counting.
  def balance_history(accounts, since: nil)
    start = Date.current - HISTORY_DAYS.days
    start = since if since && since < start
    range = start..Date.current
    daily = Transaction.where(account: accounts, posted_on: range)
                       .group(:account_id, :posted_on).sum(:amount_cents)
    pre = Transaction.where(account: accounts).where("posted_on < ?", range.begin)
                     .group(:account_id).sum(:amount_cents)
    series = accounts.map do |a|
      bal = a.opening_balance_cents + pre.fetch(a.id, 0)
      range.map do |d|
        bal += daily[[ a.id, d ]] || 0
        [ d, a.opened_on && d < a.opened_on ? 0 : bal ]
      end
    end
    range.map { |d| [ d, series.sum { |pts| pts.assoc(d).last } ] }
  end
end
