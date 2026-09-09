# Run on panel: bin/cleat_deploy rpc "Code.eval_file('priv/scripts/setup_open_drive.exs')"
alias CleatDeploy.{Accounts, Apps, Deployments, Repo, Servers}
import Ecto.Query

email = "matheus.puppe@gmail.com"
user = Accounts.get_user_by_email(email) || raise "user not found: #{email}"
scope = Accounts.ensure_scope_for_user(user)
tenant_id = scope.tenant.id

server =
  Repo.one!(from s in Servers.Server, where: s.tenant_id == ^tenant_id, limit: 1)

app_attrs = %{
  name: "OpenDrive",
  slug: "open-drive",
  github_repo: "puppe1990/OpenDrive",
  branch: "main",
  host: "drive.gestaobem.com",
  port: 4002,
  systemd_unit: "open_drive",
  release_path: "/opt/open_drive",
  server_id: server.id
}

app =
  case Apps.get_app_by_repo("puppe1990/OpenDrive") do
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
  "PORT" => "4002",
  "PHX_HOST" => "drive.gestaobem.com",
  "POOL_SIZE" => "5",
  "SECRET_KEY_BASE" => System.get_env("OPEN_DRIVE_SECRET_KEY_BASE"),
  "TURSO_DATABASE_URL" => System.get_env("OPEN_DRIVE_TURSO_DATABASE_URL"),
  "TURSO_AUTH_TOKEN" => System.get_env("OPEN_DRIVE_TURSO_AUTH_TOKEN"),
  "OPEN_DRIVE_STORAGE_ADAPTER" => "s3",
  "AWS_S3_BUCKET" => System.get_env("OPEN_DRIVE_AWS_S3_BUCKET"),
  "AWS_REGION" => System.get_env("OPEN_DRIVE_AWS_REGION"),
  "AWS_ACCESS_KEY_ID" => System.get_env("OPEN_DRIVE_AWS_ACCESS_KEY_ID"),
  "AWS_SECRET_ACCESS_KEY" => System.get_env("OPEN_DRIVE_AWS_SECRET_ACCESS_KEY")
}

for {key, value} <- env, is_binary(value) and value != "" do
  {:ok, _} = Apps.put_env_var(app, key, value)
end

{status, _} = Apps.sync_github_webhook(app)

{:ok, deployment} =
  Deployments.enqueue(app, %{git_sha: "setup-open-drive", triggered_by: "manual"})

IO.inspect(%{
  app_id: app.id,
  slug: app.slug,
  host: app.host,
  port: app.port,
  webhook: status,
  deployment_id: deployment.id
}, label: "open_drive_setup")