class RecurringRulesController < ApplicationController
  def index
    @archived = params[:archived].present?
    @rules = RecurringRule.where(active: !@archived)
                          .includes(:account, :category, :to_account).ordered
    @next = Recurring.occurrences_for(@rules, Date.current..(Date.current + 90))
                    .group_by { |o| o[:rule].id }
                    .transform_values { |os| os.first[:on] }
    @edit_rule = RecurringRule.find_by(id: params[:edit])
    @new_rule = RecurringRule.new(prefill_params) if params[:new].present?
    @accounts = Account.active.order(:name)
    @suggestions = RecurringSuggestions.call unless @archived
    @accounts_by_id = @accounts.index_by(&:id)
    @categories = Category.active.order(:kind, :name)
  end

  def create
    rule = RecurringRule.new(rule_params)
    if rule.save
      redirect_back_to_page recurring_rules_path, notice: "Rule added."
    else
      redirect_back_to_page recurring_rules_path(new: 1), alert: rule.errors.full_messages.to_sentence
    end
  end

  def update
    rule = RecurringRule.find(params[:id])
    if rule.update(rule_params)
      redirect_back_to_page recurring_rules_path, notice: "Rule saved."
    else
      redirect_back_to_page recurring_rules_path(edit: rule.id), alert: rule.errors.full_messages.to_sentence
    end
  end

  def archive
    RecurringRule.find(params[:id]).update!(active: false)
    redirect_back_to_page recurring_rules_path, notice: "Rule paused."
  end

  def unarchive
    RecurringRule.find(params[:id]).update!(active: true)
    redirect_back_to_page recurring_rules_path, notice: "Rule resumed."
  end

  private

  def rule_params
    params.require(:recurring_rule).permit(:payee, :account_id, :category_id,
      :to_account_id, :kind, :amount, :frequency, :every, :start_on, :end_on, :mask_history)
  end

  def prefill_params
    params.fetch(:prefill, {}).permit(:payee, :account_id, :kind, :amount,
      :frequency, :every, :start_on)
  end
end
