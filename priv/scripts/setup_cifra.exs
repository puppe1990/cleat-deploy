# Register Cifra (puppe1990/cifra-finops) on gestaobem-cx33.
# Does not enqueue a deploy — the unit is already running.
#
# On the production panel:
#   bin/cleat_deploy rpc "Code.eval_file(\"/tmp/setup_cifra.exs\")"
#
# Locally:
#   GITHUB_TOKEN=... mix run --no-start priv/scripts/setup_cifra.exs

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

live_env_path = System.get_env("CIFRA_ENV_FILE") || "/etc/cifra/env"
live_env = if File.exists?(live_env_path), do: parse_env_file.(live_env_path), else: %{}

email = "matheus.puppe@gmail.com"
user = Accounts.get_user_by_email(email) || raise "user not found: #{email}"
scope = Accounts.ensure_scope_for_user(user)
tenant_id = scope.tenant.id

server_name = System.get_env("CIFRA_SERVER_NAME") || "gestaobem-cx33"
host = System.get_env("CIFRA_HOST") || Map.get(live_env, "PHX_HOST") || "finops.gestaobem.com"

port =
  (System.get_env("CIFRA_PORT") || Map.get(live_env, "PORT") || "4022")
  |> String.trim_leading(":")
  |> String.to_integer()

branch = System.get_env("CIFRA_BRANCH") || "main"

server =
  Repo.one!(
    from s in Servers.Server,
      where: s.tenant_id == ^tenant_id and s.name == ^server_name,
      limit: 1
  )

app_attrs = %{
  name: "Cifra",
  slug: "cifra",
  github_repo: "puppe1990/cifra-finops",
  branch: branch,
  host: host,
  port: port,
  runtime: "golang",
  systemd_unit: "cifra",
  release_path: "/opt/cifra",
  auto_deploy: true,
  server_id: server.id
}

app =
  case Apps.get_app_by_repo("puppe1990/cifra-finops") do
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

app_secret =
  cond do
    secret = System.get_env("CIFRA_APP_SECRET") -> secret
    secret = Map.get(live_env, "APP_SECRET") -> secret
    secret = Map.get(existing_env, "APP_SECRET") -> secret
    true -> Base.encode64(:crypto.strong_rand_bytes(32))
  end

admin_token =
  cond do
    token = System.get_env("CIFRA_ADMIN_TOKEN") -> token
    token = Map.get(live_env, "ADMIN_TOKEN") -> token
    token = Map.get(existing_env, "ADMIN_TOKEN") -> token
    true -> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  end

env =
  live_env
  |> Map.merge(%{
    "PORT" => ":#{port}",
    "ENV" => Map.get(live_env, "ENV", "production"),
    "APP_URL" => "https://#{host}",
    "PHX_HOST" => host,
    "DB_PATH" => Map.get(live_env, "DB_PATH", "/opt/cifra/data/app.db"),
    "LOCALE" => Map.get(live_env, "LOCALE", "pt"),
    "TRUSTED_PROXIES" => Map.get(live_env, "TRUSTED_PROXIES", "127.0.0.1"),
    "STATIC_DIR" => Map.get(live_env, "STATIC_DIR", "/opt/cifra/current/web/static"),
    "APP_SECRET" => app_secret,
    "ADMIN_TOKEN" => admin_token
  })

for {key, value} <- env, is_binary(key) and is_binary(value) and value != "" do
  {:ok, _} = Apps.put_env_var(app, key, value)
end

{webhook_status, _} = Apps.sync_github_webhook(app)

IO.inspect(
  %{
    app_id: app.id,
    slug: app.slug,
    host: app.host,
    port: app.port,
    runtime: app.runtime,
    branch: app.branch,
    server: server.name,
    server_ip: server.host_ip,
    release_path: app.release_path,
    systemd_unit: app.systemd_unit,
    auto_deploy: app.auto_deploy,
    webhook: webhook_status,
    env_keys: env |> Map.keys() |> Enum.sort(),
    live_env_file: if(File.exists?(live_env_path), do: live_env_path, else: :missing),
    github_token: if(System.get_env("GITHUB_TOKEN") in [nil, ""], do: :missing, else: :set)
  },
  label: "cifra_setup"
)
