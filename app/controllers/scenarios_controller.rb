class ScenariosController < ApplicationController
  def create
    scenario = Scenario.create!(name: params[:name].presence || "New scenario")
    scenario.clone_live_rules!
    redirect_to recurring_rules_path(scenario_id: scenario.id), notice: "Scenario created with a copy of your live rules."
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
