# Run on panel:
#   bin/cleat_deploy rpc "Code.eval_file('priv/scripts/setup_mass_transcriptor.exs')"
alias CleatDeploy.{Accounts, Apps, Deployments, Repo, Servers}
import Ecto.Query

email = "matheus.puppe@gmail.com"
user = Accounts.get_user_by_email(email) || raise "user not found: #{email}"
scope = Accounts.ensure_scope_for_user(user)
tenant_id = scope.tenant.id

server =
  Repo.one!(from s in Servers.Server, where: s.tenant_id == ^tenant_id, limit: 1)

app_attrs = %{
  name: "Mass Transcriptor",
  slug: "mass-transcriptor",
  github_repo: "puppe1990/mass-transcriptor-phoenix",
  branch: "main",
  host: "transcribe.gestaobem.com",
  port: 4003,
  systemd_unit: "mass_transcriptor",
  release_path: "/opt/mass_transcriptor",
  server_id: server.id
}

app =
  case Apps.get_app_by_repo("puppe1990/mass-transcriptor-phoenix") do
    nil ->
      {:ok, app, _status} = Apps.create_app(scope, app_attrs)
      Apps.get_app!(scope, app.id)

    %{} = existing ->
      existing
      |> Ecto.Changeset.change(Map.put(app_attrs, :tenant_id, tenant_id))
      |> Repo.update!()
  end

env = %{
  "PHX_SERVER" => "true",
  "PORT" => "4003",
  "PHX_HOST" => "transcribe.gestaobem.com",
  "POOL_SIZE" => "2",
  "STORAGE_ROOT" => "/var/lib/mass_transcriptor/storage",
  "DATABASE_PATH" => "/var/lib/mass_transcriptor/replica.db",
  "SECRET_KEY_BASE" => System.get_env("MASS_TRANSCRIPTOR_SECRET_KEY_BASE"),
  "TURSO_DATABASE_URL" => System.get_env("MASS_TRANSCRIPTOR_TURSO_DATABASE_URL"),
  "TURSO_AUTH_TOKEN" => System.get_env("MASS_TRANSCRIPTOR_TURSO_AUTH_TOKEN"),
  "ASSEMBLYAI_API_KEY" => System.get_env("MASS_TRANSCRIPTOR_ASSEMBLYAI_API_KEY")
}

for {key, value} <- env, is_binary(value) and value != "" do
  {:ok, _} = Apps.put_env_var(app, key, value)
end

{status, _} = Apps.sync_github_webhook(app)

{:ok, deployment} =
  Deployments.enqueue(app, %{git_sha: "setup-mass-transcriptor", triggered_by: "manual"})

IO.inspect(%{
  app_id: app.id,
  slug: app.slug,
  host: app.host,
  port: app.port,
  webhook: status,
  deployment_id: deployment.id
}, label: "mass_transcriptor_setup")