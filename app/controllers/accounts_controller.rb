class AccountsController < ApplicationController
  def index
    @archived = params[:archived].present?
    @accounts = Account.where(active: !@archived).includes(:owner).order(:name)
    @edit_account = Account.find_by(id: params[:edit])
    @members = User.order(:name)
  end

  def show
    @account = Account.find(params[:id])
    @transactions = @account.transactions.includes(:category, :user)
    @transactions = @transactions.uncategorised if params[:uncategorised].present?
    @transactions = @transactions.where("payee ILIKE ?", "%#{params[:q].strip}%") if params[:q].present?
    @transactions = @transactions.ordered
    @balances = @account.running_balances
    @edit_txn = @account.transactions.find_by(id: params[:edit])
    @accounts = Account.active.order(:name)
    @categories = Category.active.order(:kind, :name)
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
    if account.update(account_params)
      redirect_back_to_page accounts_path, notice: "Account saved."
    else
      redirect_back_to_page accounts_path(edit: account.id), alert: account.errors.full_messages.to_sentence
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
    params.require(:account).permit(:name, :kind, :currency, :owner_id, :opening_balance, :notes)
  end
end
