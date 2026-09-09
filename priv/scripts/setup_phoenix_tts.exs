# Run on panel:
#   bin/cleat_deploy rpc "Code.eval_file('priv/scripts/setup_phoenix_tts.exs')"
alias CleatDeploy.{Accounts, Apps, Deployments, Repo, Servers}
import Ecto.Query

email = "matheus.puppe@gmail.com"
user = Accounts.get_user_by_email(email) || raise "user not found: #{email}"
scope = Accounts.ensure_scope_for_user(user)
tenant_id = scope.tenant.id

server =
  Repo.one!(from s in Servers.Server, where: s.tenant_id == ^tenant_id, limit: 1)

app_attrs = %{
  name: "Phoenix TTS",
  slug: "phoenix-tts",
  github_repo: "puppe1990/phoenix_tts",
  branch: "main",
  host: "tts.gestaobem.com",
  port: 4004,
  systemd_unit: "phoenix_tts",
  release_path: "/opt/phoenix_tts",
  server_id: server.id
}

app =
  case Apps.get_app_by_repo("puppe1990/phoenix_tts") do
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
  "PORT" => "4004",
  "PHX_HOST" => "tts.gestaobem.com",
  "POOL_SIZE" => "5",
  "DATABASE_PATH" => "/var/lib/phoenix_tts/replica.db",
  "SECRET_KEY_BASE" => System.get_env("PHOENIX_TTS_SECRET_KEY_BASE"),
  "TURSO_DATABASE_URL" => System.get_env("PHOENIX_TTS_TURSO_DATABASE_URL"),
  "TURSO_AUTH_TOKEN" => System.get_env("PHOENIX_TTS_TURSO_AUTH_TOKEN"),
  "ELEVENLABS_API_KEY" => System.get_env("PHOENIX_TTS_ELEVENLABS_API_KEY"),
  "ELEVENLABS_BASE_URL" => System.get_env("PHOENIX_TTS_ELEVENLABS_BASE_URL") || "https://api.elevenlabs.io",
  "ELEVENLABS_DEFAULT_OUTPUT_FORMAT" =>
    System.get_env("PHOENIX_TTS_ELEVENLABS_DEFAULT_OUTPUT_FORMAT") || "mp3_44100_128"
}

for {key, value} <- env, is_binary(value) and value != "" do
  {:ok, _} = Apps.put_env_var(app, key, value)
end

{status, _} = Apps.sync_github_webhook(app)

{:ok, deployment} =
  Deployments.enqueue(app, %{git_sha: "setup-phoenix-tts", triggered_by: "manual"})

IO.inspect(%{
  app_id: app.id,
  slug: app.slug,
  host: app.host,
  port: app.port,
  webhook: status,
  deployment_id: deployment.id
}, label: "phoenix_tts_setup")