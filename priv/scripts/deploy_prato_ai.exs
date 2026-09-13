# Deploy PratoAI via SSH runner:
#   GITHUB_TOKEN=... DEPLOY_RUNNER=ssh mix run --no-start priv/scripts/deploy_prato_ai.exs

import Ecto.Query

alias CleatDeploy.{Accounts, Apps, Deployments, Repo}
alias CleatDeploy.Deploy.SshRunner

for app <- [:crypto, :ecto_sql, :ecto_sqlite3, :cloak, :cloak_ecto, :phoenix_pubsub] do
  {:ok, _} = Application.ensure_all_started(app)
end

for child <- [CleatDeploy.Repo, CleatDeploy.Vault] do
  {:ok, _} = child.start_link()
end

{:ok, _} = Supervisor.start_link([{Phoenix.PubSub, name: CleatDeploy.PubSub}], strategy: :one_for_one)

email = "matheus.puppe@gmail.com"
user = Accounts.get_user_by_email(email) || raise "user not found: #{email}"
scope = Accounts.ensure_scope_for_user(user)

app =
  Apps.get_app_by_repo("gestao-bem/prato-ai") ||
    raise "PratoAI app not registered — run setup_prato_ai.exs first"

app = Apps.get_app!(scope, app.id)
IO.puts("==> App ##{app.id} #{app.slug} -> https://#{app.host}")

{:ok, deployment} =
  Deployments.create_deployment(app, %{git_sha: "manual", git_ref: app.branch})
IO.puts("==> Deployment ##{deployment.id} — SshRunner (several minutes)...")

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
