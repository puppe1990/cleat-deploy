defmodule CleatDeploy.Apps.ProvisioningTest do
  use CleatDeploy.DataCase

  alias CleatDeploy.Apps.Provisioning
  alias CleatDeploy.TenancyFixtures

  setup do
    scope = TenancyFixtures.scope_fixture()
    server = TenancyFixtures.server_fixture(scope, %{name: "trip-lightsail"})
    catalog_server = TenancyFixtures.server_fixture(scope, %{name: "catalogo-lightsail"})

    %{servers: [server, catalog_server], server: server, catalog_server: catalog_server}
  end

  test "preset_from_repo/2 uses known profile for trip planner", %{
    servers: servers,
    server: server
  } do
    preset = Provisioning.preset_from_repo("puppe1990/trip-planner-ia-phx", servers)

    assert preset["name"] == "Trip Planner"
    assert preset["slug"] == "trip-planner"
    assert preset["host"] == "trip.gestaobem.com"
    assert preset["github_repo"] == "puppe1990/trip-planner-ia-phx"
    assert preset["branch"] == "main"
    assert preset["server_id"] == server.id
    assert preset["systemd_unit"] == "trip_planner_ia"
    assert preset["release_path"] == "/opt/trip_planner_ia"
  end

  test "preset_from_repo/2 routes catalogo to dedicated server", %{catalog_server: catalog_server} do
    preset =
      Provisioning.preset_from_repo("gestao-bem/catalog_platform", [catalog_server])

    assert preset["slug"] == "catalogo"
    assert preset["host"] == "loja.gestaobem.com"
    assert preset["server_id"] == catalog_server.id
  end

  test "preset_from_repo/2 uses known profile for vexo on catalogo-lightsail", %{
    catalog_server: catalog_server
  } do
    preset = Provisioning.preset_from_repo("puppe1990/vexo", [catalog_server])

    assert preset["name"] == "Vexo"
    assert preset["slug"] == "vexo"
    assert preset["host"] == "vexo.gestaobem.com"
    assert preset["port"] == 4012
    assert preset["systemd_unit"] == "vexo"
    assert preset["release_path"] == "/opt/vexo"
    assert preset["server_id"] == catalog_server.id
  end

  test "preset_from_repo/2 uses golang profile for github-projects on hetzner", %{
    servers: servers
  } do
    scope = TenancyFixtures.scope_fixture()
    hetzner = TenancyFixtures.server_fixture(scope, %{name: "gestaobem-cx33"})

    preset =
      Provisioning.preset_from_repo("puppe1990/github-projects-viewer-cais", [hetzner | servers])

    assert preset["name"] == "GitHub Projects"
    assert preset["slug"] == "github-projects"
    assert preset["host"] == "github.gestaobem.com"
    assert preset["port"] == 4021
    assert preset["runtime"] == "golang"
    assert preset["systemd_unit"] == "github-projects"
    assert preset["release_path"] == "/opt/github-projects"
    assert preset["server_id"] == hetzner.id
  end

  test "preset_from_repo/2 uses golang profile for atelie on hetzner", %{
    servers: servers
  } do
    scope = TenancyFixtures.scope_fixture()
    hetzner = TenancyFixtures.server_fixture(scope, %{name: "gestaobem-cx33"})

    preset = Provisioning.preset_from_repo("puppe1990/atelie", [hetzner | servers])

    assert preset["name"] == "Ateliê"
    assert preset["slug"] == "atelie"
    assert preset["host"] == "atelie.gestaobem.com"
    assert preset["port"] == 4020
    assert preset["runtime"] == "golang"
    assert preset["systemd_unit"] == "atelie"
    assert preset["release_path"] == "/opt/atelie"
    assert preset["server_id"] == hetzner.id
  end

  test "preset_from_repo/2 derives defaults for unknown repos", %{server: server} do
    preset = Provisioning.preset_from_repo("puppe1990/my_new_app", [server])

    assert preset["name"] == "My New App"
    assert preset["slug"] == "my-new-app"
    assert preset["host"] == "my-new-app.gestaobem.com"
    assert preset["systemd_unit"] == "phx-my-new-app"
    assert preset["release_path"] == "/opt/my_new_app"
  end

  test "apply_preset/2 fills form params from selected repo", %{server: server} do
    params =
      Provisioning.apply_preset(%{"github_repo" => "puppe1990/rapid-tools"}, [server])

    assert params["name"] == "RapidTools"
    assert params["host"] == "tools.gestaobem.com"
    assert params["server_id"] == server.id
  end
end
