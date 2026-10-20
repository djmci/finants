class DashboardController < ApplicationController
  HISTORY_DAYS = 90
  LIQUID_KINDS = %w[everyday savings cash].freeze

  def index
    @accounts = Account.active.includes(:owner).order(:name)
    @uncategorised_count = Transaction.uncategorised.count
    rules = RecurringRule.active.includes(:account, :category, :to_account)
    @upcoming = Recurring.occurrences_for(rules, Date.current..(Date.current + 30))

    @months = (params[:months].presence || 6).to_i.clamp(1, 24)
    scope, @scope_label = forecast_scope
    forecast = Forecast.new(accounts: scope, rules: rules)
    @projection = forecast.combined(Date.current..(Date.current + @months.months))
    @history = balance_history(scope)
    @floor = @projection.min_by(&:last)
    @net_flow = @projection.any? ? (@projection.last.last - @projection.first.last) / @months : 0
  end

  private

  # Default = cash position (liquid accounts only — liabilities like the
  # mortgage make the chart useless). account=all → net worth view.
  def forecast_scope
    case params[:account]
    when "all"
      [@accounts, "All accounts"]
    when nil, "", "cash"
      [@accounts.select { |a| LIQUID_KINDS.include?(a.kind) }, "Cash"]
    else
      account = @accounts.detect { |a| a.id.to_s == params[:account] }
      account ? [[ account ], account.name] : [@accounts.select { |a| LIQUID_KINDS.include?(a.kind) }, "Cash"]
    end
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
