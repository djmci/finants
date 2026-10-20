class TransfersController < ApplicationController
  def create
    from = Account.active.find(params[:from_account_id])
    to = Account.active.find(params[:to_account_id])
    if from == to
      redirect_back_to_page transactions_path(transfer: 1), alert: "Pick two different accounts."
      return
    end
    Transaction.create_transfer!(
      from_account: from, to_account: to,
      posted_on: params[:posted_on], amount: params[:amount],
      notes: params[:notes], user: Current.user
    )
    redirect_back_to_page transactions_path, notice: "Transfer recorded."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back_to_page transactions_path(transfer: 1), alert: e.record.errors.full_messages.to_sentence
  end
end
