defmodule CleatDeploy.Deploy.SshRunnerTest do
  use CleatDeploy.DataCase, async: false

  alias CleatDeploy.{Apps, Deployments}
  alias CleatDeploy.Deploy.SshRunner
  alias CleatDeploy.TenancyFixtures

  setup do
    scope = TenancyFixtures.scope_fixture()

    server =
      TenancyFixtures.server_fixture(scope, %{name: "lightsail-1", host_ip: "100.59.80.29"})

    {:ok, app, _webhook_status} =
      Apps.create_app(scope, %{
        name: "Trip Planner",
        slug: "trip-planner",
        github_repo: "puppe1990/trip-planner-ia-phx",
        host: "trip.gestaobem.com",
        server_id: server.id
      })

    {:ok, deployment} = Deployments.create_deployment(app, %{git_sha: "manual"})
    %{deployment: deployment}
  end

  test "returns error when SSH key is missing", %{deployment: deployment} do
    assert {:error, "SSH private key not configured on server"} =
             SshRunner.deploy(deployment)
  end
end
