# Deploy CLARITY AI via the local PaaS DB + SSH runner.
#
#   GITHUB_TOKEN=... mix run --no-start priv/scripts/deploy_clarity.exs

for app <- [:crypto, :ecto_sql, :ecto_sqlite3, :cloak, :cloak_ecto, :finch, :req] do
  {:ok, _} = Application.ensure_all_started(app)
end

for child <- [CleatDeploy.Repo, CleatDeploy.Vault] do
  {:ok, _} = child.start_link()
end

alias CleatDeploy.{Apps, Deployments, Repo, Servers}
alias CleatDeploy.Apps.App
alias CleatDeploy.Deploy.SshRunner

app =
  case Apps.get_app_by_repo("puppe1990/assistente-ia") do
    %App{} = existing -> existing
    nil -> raise "CLARITY AI app not registered — run priv/scripts/setup_clarity.exs first"
  end

app = Apps.get_app!(app.id)
server = Repo.get!(Servers.Server, app.server_id)

IO.puts("==> Deploying #{app.slug} (release=#{App.release_name(app.slug)})")
IO.puts("==> https://#{app.host} via #{server.name} @ #{server.host_ip}")

{:ok, deployment} =
  Deployments.create_deployment(app, %{git_sha: "manual", git_ref: app.branch || "main"})

IO.puts("==> Deployment ##{deployment.id} — running SshRunner...")

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
