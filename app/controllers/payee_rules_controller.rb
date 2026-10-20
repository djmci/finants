class PayeeRulesController < ApplicationController
  def create
    rule = PayeeRule.new(rule_params)
    if rule.save
      redirect_back_to_page categories_path(tab: "rules"), notice: "Rule added."
    else
      redirect_back_to_page categories_path(tab: "rules"), alert: rule.errors.full_messages.to_sentence
    end
  end

  def update
    rule = PayeeRule.find(params[:id])
    if rule.update(rule_params)
      redirect_back_to_page categories_path(tab: "rules"), notice: "Rule saved."
    else
      redirect_back_to_page categories_path(tab: "rules"), alert: rule.errors.full_messages.to_sentence
    end
  end

  def destroy
    PayeeRule.find(params[:id]).destroy
    redirect_back_to_page categories_path(tab: "rules"), notice: "Rule removed."
  end

  private

  def rule_params
    permitted = params.require(:payee_rule)
                      .permit(:pattern, :category_id, :round_amount, :direction, :auto, :max_amount)
    {
      pattern: permitted[:pattern],
      category_id: permitted[:category_id],
      round_amount: permitted[:round_amount].presence&.then { |v| v == "true" },
      direction: permitted[:direction].presence,
      auto: permitted[:auto] == "1",
      max_amount_cents: permitted[:max_amount].present? ? (permitted[:max_amount].to_d * 100).to_i : nil
    }
  end
end
