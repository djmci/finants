class AccountsController < ApplicationController
  def index
    @archived = params[:archived].present?
    @accounts = Account.where(active: !@archived).includes(:owner, :successors).order(:name)
    @edit_account = Account.find_by(id: params[:edit])
    @members = User.order(:name)

    # Balance at each recent month-end — account opening + txns to date.
    @history_dates = (5.downto(1).map { |m| (Date.current - m.months).end_of_month } + [ Date.current ]).uniq
    sums = @history_dates.index_with do |d|
      Transaction.where("posted_on <= ?", d).group(:account_id).sum(:amount_cents)
    end
    @balance_history = @accounts.to_h do |a|
      [ a.id, @history_dates.map { |d| d < (a.opened_on || Date.new(1)) ? 0 : a.opening_balance_cents + sums[d].fetch(a.id, 0) } ]
    end
  end

  def show
    @account = Account.find(params[:id])
    @transactions = @account.transactions.includes(:category, :user)
    @transactions = @transactions.uncategorised if params[:uncategorised].present?
    @transactions = @transactions.where("payee ILIKE ?", "%#{params[:q].strip}%") if params[:q].present?
    @transactions = @transactions.ordered
    @balances = @account.running_balances
    @pages = (@transactions.count.to_f / TransactionsController::PAGE_SIZE).ceil
    @page = params[:page].to_i.clamp(1, [ @pages, 1 ].max)
    @transactions = @transactions.offset((@page - 1) * TransactionsController::PAGE_SIZE).limit(TransactionsController::PAGE_SIZE)
    @edit_txn = @account.transactions.find_by(id: params[:edit])
    @accounts = Account.active.order(:name)
    @categories = Category.active.order(:kind, :name)
    @once_rules = RecurringRule.live.active.where(frequency: "once").includes(:account).order(:payee)
  end

  def create
    account = Account.new(account_params)
    if account.save
      redirect_back_to_page accounts_path, notice: "Account added."
    else
      redirect_back_to_page accounts_path(new: 1), alert: account.errors.full_messages.to_sentence
    end
  end

  def update
    account = Account.find(params[:id])
    unless account.update(account_params)
      return redirect_back_to_page accounts_path(edit: account.id), alert: account.errors.full_messages.to_sentence
    end
    on = params[:closed_on].presence&.to_date
    successor = Account.active.where.not(id: account.id).find_by(id: params[:succeeded_by_id])
    if account.active?
      if params[:succeeded_by_id] == "close"
        account.handover_to!(nil, on:)
        redirect_back_to_page accounts_path, notice: "Account closed out."
      elsif successor && !account.successors.include?(successor)
        account.handover_to!(successor, on:)
        redirect_back_to_page accounts_path, notice: "Closed and handed over to #{successor.name}."
      else
        redirect_back_to_page accounts_path, notice: "Account saved."
      end
    else
      # Archived: revisit the closure — re-date it, or attach a
      # successor the original handover missed.
      account.redate_closure!(on) if on
      if successor && !account.successors.include?(successor)
        account.link_successor!(successor)
        redirect_back_to_page accounts_path, notice: "Handed over to #{successor.name}."
      else
        redirect_back_to_page accounts_path, notice: "Closure details saved."
      end
    end
  end

  def archive
    Account.find(params[:id]).update!(active: false)
    redirect_back_to_page accounts_path, notice: "Account archived."
  end

  def unarchive
    Account.find(params[:id]).update!(active: true)
    redirect_back_to_page accounts_path, notice: "Account restored."
  end

  private

  def account_params
    params.require(:account).permit(:name, :kind, :currency, :owner_id, :opening_balance, :opened_on, :notes)
  end
end
