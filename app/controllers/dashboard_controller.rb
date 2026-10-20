class DashboardController < ApplicationController
  def index
    @accounts = Account.active.includes(:owner).order(:name)
    @uncategorised_count = Transaction.uncategorised.count
    rules = RecurringRule.active.includes(:account, :category, :to_account)
    @upcoming = Recurring.occurrences_for(rules, Date.current..(Date.current + 30))
  end
end
