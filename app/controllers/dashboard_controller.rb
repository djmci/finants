class DashboardController < ApplicationController
  def index
    @accounts = Account.active.includes(:owner).order(:name)
    @uncategorised_count = Transaction.uncategorised.count
  end
end
