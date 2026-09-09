defmodule CleatDeployWeb.PaasComponentsTest do
  use ExUnit.Case, async: true

  alias CleatDeployWeb.PaasComponents

  test "filter_repo_options/3 matches repo names case-insensitively" do
    repos = [
      {"puppe1990/trip-planner-ia-phx", "puppe1990/trip-planner-ia-phx"},
      {"puppe1990/rapid-tools", "puppe1990/rapid-tools"}
    ]

    assert PaasComponents.filter_repo_options(repos, "TRIP") == [
             {"puppe1990/trip-planner-ia-phx", "puppe1990/trip-planner-ia-phx"}
           ]
  end

  test "filter_repo_options/3 limits visible results" do
    repos = Enum.map(1..60, fn n -> {"org/repo-#{n}", "org/repo-#{n}"} end)

    assert length(PaasComponents.filter_repo_options(repos, "")) == 50
    assert PaasComponents.count_repo_matches(repos, "") == 60
  end
end
