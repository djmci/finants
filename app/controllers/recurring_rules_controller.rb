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
    load_coverage if @edit_rule&.persisted? && @edit_rule.scenario_id.nil?
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

  # Claim a payee for this rule: record the coverage pattern, then link
  # every matching txn on the rule's account — whatever the amount.
  def link_payee
    rule = RecurringRule.live.find(params[:id])
    pattern = PayeeRule.detection_key(params[:payee])
    return redirect_back_to_page(recurring_rules_path, alert: "No payee to match.") if pattern.blank?

    payee_rule = PayeeRule.find_or_initialize_by(pattern:, round_amount: nil,
                                                 direction: nil, max_amount_cents: nil)
    payee_rule.update!(recurring_rule: rule)

    # Transfers and settles claim both legs — the payee pattern names
    # the counterparty on both sides.
    scope = direction_scope(Transaction.where(recurring_rule_id: nil, transfer_pair_id: nil), rule.kind)
    ids = scope.pluck(:id, :payee)
               .select { |_, payee| PayeeRule.detection_key(payee).include?(pattern) }
               .map(&:first)
    Transaction.where(id: ids).update_all(recurring_rule_id: rule.id)
    rule.update!(active: false) if rule.frequency == "once" && ids.any?
    redirect_back_to_page recurring_rules_path(edit: rule.id),
      notice: "#{payee_rule.pattern} covered — #{ids.size} transaction#{"s" unless ids.size == 1} linked."
  end

  # Drop a claim: matching txns unlink (they re-enter drift) and the
  # coverage pattern goes unless it also categorises.
  def unlink_payee
    rule = RecurringRule.live.find(params[:id])
    payee_rule = rule.payee_rules.find(params[:payee_rule_id])
    pattern = payee_rule.pattern
    if payee_rule.category_id.present?
      payee_rule.update!(recurring_rule_id: nil)
    else
      payee_rule.destroy!
    end
    ids = rule.transactions.pluck(:id, :payee)
             .select { |_, payee| PayeeRule.detection_key(payee).include?(pattern) }
             .map(&:first)
    Transaction.where(id: ids).update_all(recurring_rule_id: nil)
    redirect_back_to_page recurring_rules_path(edit: rule.id),
      notice: "#{pattern} uncovered — #{ids.size} transaction#{"s" unless ids.size == 1} unlinked."
  end

  private

  # Covered patterns + linkable payees for the edit drawer: distinct
  # ref-stripped payee keys among unlinked txns on ANY account (coverage
  # is household-level), newest half-year. Payees already carrying the
  # rule's category sort first — they're the likely claim — then the
  # rest by frequency. The drawer filters this list client-side.
  def load_coverage
    @coverage = @edit_rule.payee_rules.order(:pattern)
    rows = direction_scope(
      Transaction.where(recurring_rule_id: nil, transfer_pair_id: nil)
                 .where(posted_on: (Date.current - 180)..)
                 .joins(:account), @edit_rule.kind
    ).pluck(:payee, :category_id, "accounts.name")
    grouped = rows.group_by { |(payee, _, _)| PayeeRule.detection_key(payee) }
    covered = @coverage.map(&:pattern)
    # The rule's category (and its children) marks likely claims.
    cat_ids = [ @edit_rule.category_id, *@edit_rule.category&.children&.ids ].compact
    @coverage_candidates = grouped.filter_map do |key, list|
      next if key.blank? || covered.any? { |pat| key.include?(pat) }
      [ key, list.size, list.map(&:last).compact.uniq.sort.join(", "),
        list.any? { |(_, cid, _)| cat_ids.include?(cid) } ]
    end.sort_by { |(_, n, _, match)| [ match ? 0 : 1, -n ] }.first(40)
  end

  # Expense rules claim outflows, income claims inflows; transfers and
  # settles name a counterparty and claim either direction.
  def direction_scope(scope, kind)
    case kind
    when "expense" then scope.where("amount_cents < 0")
    when "income"  then scope.where("amount_cents > 0")
    else scope
    end
  end

  def rule_params
    params.require(:recurring_rule).permit(:payee, :account_id, :category_id,
      :to_account_id, :kind, :amount, :frequency, :every, :max_per_year, :start_on, :end_on, :include_in_hybrid, :scenario_id)
  end

  def prefill_params
    params.fetch(:prefill, {}).permit(:payee, :account_id, :kind, :amount,
      :frequency, :every, :start_on)
  end
end
