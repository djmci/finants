require "test_helper"

class ScenariosControllerTest < ActionDispatch::IntegrationTest
  test "forecast page shows rename form for the active scenario" do
    sign_in_as users(:one)
    scenario = Scenario.create!(name: "Top up")
    get recurring_rules_url(scenario_id: scenario.id)
    assert_response :success
    assert_select "form[action=?][method=post]", scenario_path(scenario) do
      assert_select "input[name=_method][value=patch]"
      assert_select "input[name=name][value=?]", "Top up"
    end
  end

  test "promote swaps scenario rules with the live set and keeps the old ones" do
    sign_in_as users(:one)
    scenario = Scenario.create!(name: "Top up")
    adopted = scenario.recurring_rules.create!(payee: "SCENARIO BILL", account: accounts(:everyday),
      kind: "expense", amount_cents: 10000, frequency: "monthly", start_on: Date.current)

    post promote_scenario_url(scenario), params: { archive_name: "Old plan" }

    assert_nil adopted.reload.scenario_id
    assert_equal scenario.id, recurring_rules(:rent).reload.scenario_id
    assert_equal scenario.id, recurring_rules(:paycheck).reload.scenario_id
    assert_equal "Old plan", scenario.reload.name
    assert_redirected_to recurring_rules_url
  end

  test "promote retargets transaction links to the adopted counterpart" do
    sign_in_as users(:one)
    rent = recurring_rules(:rent)
    txn = Transaction.create!(account: accounts(:everyday), posted_on: Date.current - 30,
                              payee: "LANDLORD RENT", amount_cents: -200000, recurring_rule: rent)
    scenario = Scenario.create!(name: "Plan")
    adopted = scenario.recurring_rules.create!(payee: "LANDLORD RENT", account: accounts(:everyday),
      kind: "expense", amount_cents: 250000, frequency: "monthly", start_on: Date.current)

    post promote_scenario_url(scenario), params: {}

    assert_equal adopted.id, txn.reload.recurring_rule_id
  end

  test "promote is reversible — the displaced plan can be adopted back" do
    sign_in_as users(:one)
    scenario = Scenario.create!(name: "Top up")
    adopted = scenario.recurring_rules.create!(payee: "SCENARIO BILL", account: accounts(:everyday),
      kind: "expense", amount_cents: 10000, frequency: "monthly", start_on: Date.current)
    post promote_scenario_url(scenario), params: { archive_name: "Old plan" }

    post promote_scenario_url(scenario), params: {}

    assert_nil recurring_rules(:rent).reload.scenario_id
    assert_equal scenario.id, adopted.reload.scenario_id
  end

  test "update renames the scenario" do
    sign_in_as users(:one)
    scenario = Scenario.create!(name: "Top up")
    patch scenario_url(scenario), params: { name: "Renamed" },
          headers: { "HTTP_REFERER" => recurring_rules_url(scenario_id: scenario.id) }
    assert_equal "Renamed", scenario.reload.name
    assert_redirected_to recurring_rules_url(scenario_id: scenario.id)
  end

  test "update ignores blank name" do
    sign_in_as users(:one)
    scenario = Scenario.create!(name: "Top up")
    patch scenario_url(scenario), params: { name: " " },
          headers: { "HTTP_REFERER" => recurring_rules_url(scenario_id: scenario.id) }
    assert_equal "Top up", scenario.reload.name
  end
end
