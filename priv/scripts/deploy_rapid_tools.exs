# Deploy rapid-tools to Lightsail:
#   DEPLOY_RUNNER=ssh mix run --no-start priv/scripts/deploy_rapid_tools.exs

import Ecto.Query

alias CleatDeploy.{Apps, Deployments, Repo, Seeds}
alias CleatDeploy.Deploy.SshRunner

for app <- [:crypto, :ecto_sql, :ecto_sqlite3, :cloak, :cloak_ecto] do
  {:ok, _} = Application.ensure_all_started(app)
end

for child <- [CleatDeploy.Repo, CleatDeploy.Vault] do
  {:ok, _} = child.start_link()
end

{:ok, %{scope: scope, server: server}} = Seeds.run()

IO.puts("==> Server ##{server.id} #{server.name} @ #{server.host_ip}")

app =
  case Apps.get_app_by_repo("puppe1990/rapid-tools") do
    %Apps.App{tenant_id: tenant_id} = existing when tenant_id == scope.tenant.id ->
      IO.puts("    Reusing app ##{existing.id}")
      existing

    nil ->
      {:ok, app} =
        Apps.create_app(scope, %{
          name: "RapidTools",
          slug: "rapid-tools",
          github_repo: "puppe1990/rapid-tools",
          branch: "main",
          host: "tools.gestaobem.com",
          port: 4001,
          systemd_unit: "rapid_tools",
          release_path: "/opt/rapid_tools",
          server_id: server.id
        })

      IO.puts("    Created app ##{app.id}")
      app

    other ->
      IO.puts("    App exists under another tenant (##{other.id}), reassigning")
      other
      |> Ecto.Changeset.change(%{tenant_id: scope.tenant.id, server_id: server.id})
      |> Repo.update!()
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