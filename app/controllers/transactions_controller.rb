class TransactionsController < ApplicationController
  PAGE_SIZE = 100

  def index
    @transactions = Transaction.includes(:account, :category, :user, :recurring_rule).ordered
    @transactions = @transactions.where(account_id: params[:account]) if params[:account].present?
    @transactions = @transactions.uncategorised if params[:uncategorised].present?
    @transactions = @transactions.for_owner(params[:owner]) if params[:owner].present?
    @transactions = @transactions.where("payee ILIKE ?", "%#{params[:q].strip}%") if params[:q].present?
    @pages = (@transactions.count.to_f / PAGE_SIZE).ceil
    @page = params[:page].to_i.clamp(1, [ @pages, 1 ].max)
    @transactions = @transactions.offset((@page - 1) * PAGE_SIZE).limit(PAGE_SIZE)
    @edit_txn = Transaction.find_by(id: params[:edit])
    @accounts = Account.active.order(:name)
    @categories = Category.active.order(:kind, :name)
    @members = User.order(:name)
    @uncategorised_count = Transaction.uncategorised.count
    @once_rules = RecurringRule.active.where(frequency: "once").includes(:account).order(:payee)
    @suggestions = suggest_categories(@transactions.select { |t| t.category_id.nil? })
  end

  def create
    txn = Transaction.new(txn_params)
    txn.user = Current.user
    apply_direction(txn)
    if txn.save
      redirect_back_to_page transactions_path, notice: "Transaction added."
    else
      redirect_back_to_page transactions_path(new: 1), alert: txn.errors.full_messages.to_sentence
    end
  end

  def update
    txn = Transaction.find(params[:id])
    txn.assign_attributes(txn_params)
    apply_direction(txn)
    if txn.save
      redirect_back_to_page transactions_path, anchor: "transaction_#{txn.id}", notice: "Transaction saved."
    else
      redirect_back_to_page transactions_path(edit: txn.id), alert: txn.errors.full_messages.to_sentence
    end
  end

  # One-click tag from an uncategorised pill — swaps just the cell.
  def categorise
    @txn = Transaction.find(params[:id])
    @txn.update!(category_id: params[:category_id])
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back_to_page transactions_path(anchor: "transaction_#{@txn.id}"), notice: "Transaction saved." }
    end
  end

  def destroy
    txn = Transaction.find(params[:id])
    Transaction.transaction do
      txn.transfer_pair&.destroy
      txn.destroy
    end
    redirect_back_to_page transactions_path, notice: "Transaction deleted."
  end

  private

  def txn_params
    params.require(:transaction).permit(:account_id, :posted_on, :payee, :amount, :category_id, :notes, :recurring_rule_id)
  end

  def apply_direction(txn)
    txn.amount_cents = -txn.amount_cents.abs if params.dig(:transaction, :direction) == "expense"
    txn.amount_cents = txn.amount_cents.abs if params.dig(:transaction, :direction) == "income"
  end

  # {txn_id => Category} — one-click category guesses for uncategorised
  # rows: learned payee rule → majority category of same-payee siblings
  # → a category name appearing in the ref-stripped payee.
  def suggest_categories(uncategorised)
    return {} if uncategorised.empty?
    sibling_cats = Transaction.where.not(category_id: nil).includes(:category)
                              .group_by { |t| PayeeRule.detection_key(t.payee) }
                              .transform_values { |ts| ts.group_by(&:category).max_by { |_, list| list.size }&.first }
    names = Category.active.to_a
    uncategorised.to_h do |t|
      key = PayeeRule.detection_key(t.payee)
      guess = PayeeRule.for(t.payee) || sibling_cats[key] ||
              (names.detect { |c| key.include?(PayeeRule.normalize(c.name)) } if key.present?)
      [ t.id, guess ]
    end.compact
  end
end
