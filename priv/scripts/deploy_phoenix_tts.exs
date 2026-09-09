# Deploy phoenix_tts to Lightsail:
#   DEPLOY_RUNNER=ssh mix run --no-start priv/scripts/deploy_phoenix_tts.exs

import Ecto.Query

alias CleatDeploy.{Accounts, Apps, Deployments, Repo, Servers}
alias CleatDeploy.Apps.App
alias CleatDeploy.Deploy.SshRunner

for app <- [:crypto, :ecto_sql, :ecto_sqlite3, :cloak, :cloak_ecto] do
  {:ok, _} = Application.ensure_all_started(app)
end

for child <- [CleatDeploy.Repo, CleatDeploy.Vault] do
  {:ok, _} = child.start_link()
end

email = "matheus.puppe@gmail.com"
user = Accounts.get_user_by_email(email) || raise "user not found: #{email}"
scope = Accounts.ensure_scope_for_user(user)
tenant_id = scope.tenant.id

server =
  Repo.one!(from s in Servers.Server, where: s.tenant_id == ^tenant_id, limit: 1)

IO.puts("==> Server ##{server.id} #{server.name} @ #{server.host_ip}")

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
      %App{}
      |> App.changeset(Map.put(app_attrs, :tenant_id, tenant_id))
      |> Repo.insert!()

    %{} = existing ->
      existing
      |> Ecto.Changeset.change(Map.put(app_attrs, :tenant_id, tenant_id))
      |> Repo.update!()
  end

app = Apps.get_app!(app.id)

IO.puts("    App ##{app.id} #{app.slug} -> https://#{app.host}")

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