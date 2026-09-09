defmodule CleatDeploy.Workers.DeployWorkerTest do
  use CleatDeploy.DataCase, async: false

  import Mox

  use Oban.Testing,
    repo: CleatDeploy.Repo,
    notifier: Oban.Notifiers.Isolated,
    testing: :manual

  alias CleatDeploy.{Deployments, Workers.DeployWorker}
  alias CleatDeploy.Deploy.RunnerMock
  alias CleatDeploy.TenancyFixtures

  setup :verify_on_exit!

  setup do
    scope = TenancyFixtures.scope_fixture()
    server = TenancyFixtures.server_fixture(scope)
    app = TenancyFixtures.app_fixture(scope, server)
    %{app: app}
  end

  test "marks deployment successful when runner succeeds", %{app: app} do
    expect(RunnerMock, :deploy, fn deployment ->
      assert deployment.status == :running
      {:ok, "deploy ok"}
    end)

    {:ok, deployment} = Deployments.create_deployment(app, %{git_sha: "abc123"})
    assert :ok = perform_job(DeployWorker, %{"deployment_id" => deployment.id})

    deployment = Deployments.for_app(app) |> List.first()
    assert deployment.status == :success
  end

  test "marks deployment failed when runner errors", %{app: app} do
    expect(RunnerMock, :deploy, fn _deployment -> {:error, "ssh failed"} end)

    {:ok, deployment} = Deployments.create_deployment(app, %{git_sha: "abc123"})
    assert {:error, "ssh failed"} = perform_job(DeployWorker, %{"deployment_id" => deployment.id})

    deployment = Deployments.for_app(app) |> List.first()
    assert deployment.status == :failed
  end

  test "snoozes when another deploy is already running on the same server", %{app: app} do
    {:ok, first} = Deployments.create_deployment(app, %{git_sha: "first"})
    {:ok, _} = Deployments.mark_running(first)

    {:ok, second} = Deployments.create_deployment(app, %{git_sha: "second"})

    assert {:snooze, 20} = perform_job(DeployWorker, %{"deployment_id" => second.id})

    second = Deployments.get_deployment!(second.id)
    assert second.status == :queued
  end
end
