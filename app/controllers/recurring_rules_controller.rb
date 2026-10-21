class RecurringRulesController < ApplicationController
  def index
    @tab = params[:tab].presence || (params[:archived].present? ? "paused" : "active")
    @scenario = Scenario.find_by(id: params[:scenario_id])
    @scenarios = Scenario.order(:name)
    rule_set = @scenario ? @scenario.recurring_rules : RecurringRule.live
    @rules = rule_set.where(active: @tab != "paused")
                          .includes(:account, :category, :to_account).ordered
    @next = Recurring.occurrences_for(@rules, Date.current..(Date.current + 90))
                    .group_by { |o| o[:rule].id }
                    .transform_values { |os| os.first[:on] }
    @edit_rule = RecurringRule.find_by(id: params[:edit])
    @new_rule = RecurringRule.new(prefill_params) if params[:new].present?
    @new_rule&.scenario = @scenario
    @accounts = Account.active.order(:name)
    @accounts_by_id = @accounts.index_by(&:id)
    @categories = Category.active.order(:kind, :name)

    @tab = "active" if @tab == "calendar"
    @suggestions = RecurringSuggestions.call if @tab == "detected"
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
      :to_account_id, :kind, :amount, :installments, :frequency, :every, :start_on, :end_on, :include_in_hybrid, :scenario_id)
  end

  def prefill_params
    params.fetch(:prefill, {}).permit(:payee, :account_id, :kind, :amount,
      :frequency, :every, :start_on)
  end
end
