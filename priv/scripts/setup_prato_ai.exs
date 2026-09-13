# Register PratoAI on the shared Hetzner CX33.
#
# Port 4007: 4006 is already Trama Brás on this host.
#
# Local:
#   GITHUB_TOKEN=... \
#   PRATO_AI_TURSO_DATABASE_URL=libsql://... \
#   PRATO_AI_TURSO_AUTH_TOKEN=... \
#   mix run --no-start priv/scripts/setup_prato_ai.exs
#
# Production panel:
#   bin/cleat_deploy rpc "Code.eval_file(\"/tmp/setup_prato_ai.exs\")"

unless Process.whereis(CleatDeploy.Repo) do
  for app <- [:crypto, :ecto_sql, :ecto_sqlite3, :cloak, :cloak_ecto, :finch, :req] do
    {:ok, _} = Application.ensure_all_started(app)
  end

  for child <- [CleatDeploy.Repo, CleatDeploy.Vault] do
    {:ok, _} = child.start_link()
  end

  webhook_host =
    System.get_env("PAAS_WEBHOOK_HOST") ||
      System.get_env("PHX_HOST") ||
      "paas.gestaobem.com"

  Application.put_env(:cleat_deploy, CleatDeployWeb.Endpoint,
    server: false,
    url: [host: webhook_host, port: 443, scheme: "https"]
  )

  {:ok, _} = CleatDeployWeb.Endpoint.start_link()
end

alias CleatDeploy.{Accounts, Apps, Repo, Servers}
import Ecto.Query

parse_env_file = fn path ->
  case File.read(path) do
    {:ok, contents} ->
      contents
      |> String.split("\n")
      |> Enum.reduce(%{}, fn line, acc ->
        line = String.trim(line)

        cond do
          line == "" or String.starts_with?(line, "#") ->
            acc

          true ->
            case String.split(line, "=", parts: 2) do
              [key, value] ->
                key =
                  key
                  |> String.trim()
                  |> String.replace_prefix("export ", "")

                value =
                  value
                  |> String.trim()
                  |> String.trim("\"")
                  |> String.trim("'")

                Map.put(acc, key, value)

              _ ->
                acc
            end
        end
      end)

    {:error, _} ->
      %{}
  end
end

live_env_path = System.get_env("PRATO_AI_ENV_FILE") || "/etc/prato_ai/env"
live_env = if File.exists?(live_env_path), do: parse_env_file.(live_env_path), else: %{}

email = "matheus.puppe@gmail.com"
user = Accounts.get_user_by_email(email) || raise "user not found: #{email}"
scope = Accounts.ensure_scope_for_user(user)
tenant_id = scope.tenant.id

server =
  Repo.one!(
    from s in Servers.Server,
      where: s.tenant_id == ^tenant_id and s.name == "gestaobem-cx33",
      limit: 1
  )

port =
  (System.get_env("PRATO_AI_PORT") || Map.get(live_env, "PORT") || "4007")
  |> String.trim_leading(":")
  |> String.to_integer()

secret =
  System.get_env("PRATO_AI_SECRET_KEY_BASE") ||
    Map.get(live_env, "SECRET_KEY_BASE") ||
    Base.encode64(:crypto.strong_rand_bytes(48))

app_attrs = %{
  name: "PratoAI",
  slug: "prato-ai",
  github_repo: "gestao-bem/prato-ai",
  branch: System.get_env("PRATO_AI_BRANCH") || "main",
  host: System.get_env("PRATO_AI_HOST") || "pratoai.gestaobem.com",
  port: port,
  systemd_unit: "prato_ai",
  release_path: "/opt/prato_ai",
  auto_deploy: true,
  runtime: "phoenix",
  server_id: server.id
}

app =
  case Apps.get_app_by_repo("gestao-bem/prato-ai") do
    nil ->
      {:ok, app, _status} = Apps.create_app(scope, app_attrs)
      Apps.get_app!(scope, app.id)

    %{} = existing ->
      existing
      |> Ecto.Changeset.change(Map.put(app_attrs, :tenant_id, tenant_id))
      |> Repo.update!()
      |> then(&Apps.get_app!(scope, &1.id))
  end

existing_env = Apps.env_map(app)

env = %{
  "PHX_SERVER" => "true",
  "PORT" => Integer.to_string(port),
  "PHX_HOST" => app.host,
  "POOL_SIZE" => Map.get(live_env, "POOL_SIZE") || Map.get(existing_env, "POOL_SIZE") || "5",
  "SECRET_KEY_BASE" =>
    System.get_env("PRATO_AI_SECRET_KEY_BASE") ||
      Map.get(live_env, "SECRET_KEY_BASE") ||
      Map.get(existing_env, "SECRET_KEY_BASE") ||
      secret,
  "SEED_DEMO" => Map.get(live_env, "SEED_DEMO") || Map.get(existing_env, "SEED_DEMO") || "true",
  "TURSO_DATABASE_URL" =>
    System.get_env("PRATO_AI_TURSO_DATABASE_URL") ||
      Map.get(live_env, "TURSO_DATABASE_URL") ||
      Map.get(existing_env, "TURSO_DATABASE_URL"),
  "TURSO_AUTH_TOKEN" =>
    System.get_env("PRATO_AI_TURSO_AUTH_TOKEN") ||
      Map.get(live_env, "TURSO_AUTH_TOKEN") ||
      Map.get(existing_env, "TURSO_AUTH_TOKEN"),
  "MESHY_API_KEY" =>
    System.get_env("PRATO_AI_MESHY_API_KEY") ||
      System.get_env("MESHY_API_KEY") ||
      Map.get(live_env, "MESHY_API_KEY") ||
      Map.get(existing_env, "MESHY_API_KEY")
}

for {key, value} <- env, is_binary(value) and value != "" do
  {:ok, _} = Apps.put_env_var(app, key, value)
end

{webhook_status, _} = Apps.sync_github_webhook(app)

IO.inspect(
  %{
    app_id: app.id,
    slug: app.slug,
    host: app.host,
    port: app.port,
    server: server.name,
    server_ip: server.host_ip,
    webhook: webhook_status
  },
  label: "prato_ai_setup"
)
