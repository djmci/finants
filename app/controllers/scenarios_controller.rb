class ScenariosController < ApplicationController
  def create
    source = Scenario.find_by(id: params[:source_id])
    scenario = Scenario.create!(name: params[:name].presence || "New scenario")
    scenario.clone_rules_from!(source ? source.recurring_rules : RecurringRule.live)
    redirect_to recurring_rules_path(scenario_id: scenario.id),
                notice: "Scenario created with a copy of #{source ? "#{source.name}'s" : "your live"} rules."
  end

  def resync
    scenario = Scenario.find(params[:id])
    scenario.clone_live_rules!
    redirect_to recurring_rules_path(scenario_id: scenario.id), notice: "Scenario resynced from live rules."
  end

  def destroy
    Scenario.find(params[:id]).destroy!
    redirect_back_to_page recurring_rules_path, notice: "Scenario deleted."
  end
end
