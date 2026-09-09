# One-off real deploy test — run with:
#   DEPLOY_RUNNER=ssh mix run --no-start priv/scripts/run_deploy_test.exs

import Ecto.Query

alias CleatDeploy.{Apps, Deployments, Repo, Servers}
alias CleatDeploy.Deploy.SshRunner

for app <- [:crypto, :ecto_sql, :ecto_sqlite3, :cloak, :cloak_ecto] do
  {:ok, _} = Application.ensure_all_started(app)
end

for child <- [CleatDeploy.Repo, CleatDeploy.Vault] do
  {:ok, _} = child.start_link()
end

ssh_key_path = Path.expand("~/.ssh/lightsail-default-key-us-east-1.pem")
ssh_key = File.read!(ssh_key_path)

IO.puts("==> Setting up server and app")

server =
  case Repo.one(from s in Servers.Server, where: s.host_ip == "100.59.80.29", limit: 1) do
    nil ->
      {:ok, server} =
        Servers.create_server(%{
          name: "trip-lightsail",
          host_ip: "100.59.80.29",
          ssh_user: "ubuntu",
          region: "us-east-1",
          ssh_private_key: ssh_key
        })

      server

    existing ->
      IO.puts("    Reusing server ##{existing.id}")
      existing
  end

IO.puts("    Server ##{server.id} #{server.name} @ #{server.host_ip}")

app =
  case Apps.get_app_by_repo("puppe1990/trip-planner-ia-phx") do
    nil ->
      {:ok, app} =
        Apps.create_app(%{
          name: "Trip Planner",
          slug: "trip-planner",
          github_repo: "puppe1990/trip-planner-ia-phx",
          branch: "main",
          host: "trip.gestaobem.com",
          server_id: server.id
        })

      app

    existing ->
      IO.puts("    Reusing app ##{existing.id}")
      existing
  end

IO.puts("    App ##{app.id} #{app.slug} -> https://#{app.host}")

{:ok, deployment} = Deployments.create_deployment(app, %{git_sha: "manual", git_ref: "main"})
IO.puts("==> Deployment ##{deployment.id} — running SshRunner (may take several minutes)...")

started_at = System.monotonic_time(:second)

with {:ok, running} <- Deployments.mark_running(deployment),
     running = Deployments.get_deployment!(running.id),
     {:ok, message} <- SshRunner.deploy(running),
     {:ok, _} <- Deployments.mark_success(running, message) do
  elapsed = System.monotonic_time(:second) - started_at
  IO.puts("\n==> DEPLOY SUCCESS (#{elapsed}s)")
  IO.puts(message)
  System.halt(0)
else
  {:error, reason} ->
    message = if is_binary(reason), do: reason, else: inspect(reason)
    _ = Deployments.mark_failed(Deployments.get_deployment!(deployment.id), message)
    elapsed = System.monotonic_time(:second) - started_at
    IO.puts("\n==> DEPLOY FAILED (#{elapsed}s)")
    IO.puts(message)
    System.halt(1)
end