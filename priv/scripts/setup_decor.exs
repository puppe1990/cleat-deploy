# Register Gestão Bem Decor on the Lightsail host that serves decor.gestaobem.com.
#
#   GITHUB_TOKEN=... DEPLOY_RUNNER=ssh mix run --no-start priv/scripts/setup_decor.exs
#
# Important: DNS for decor.gestaobem.com must match DECOR_SERVER_IP (default 52.73.89.19).

for app <- [:crypto, :ecto_sql, :ecto_sqlite3, :cloak, :cloak_ecto, :finch, :req] do
  {:ok, _} = Application.ensure_all_started(app)
end

for child <- [PhoenixPaas.Repo, PhoenixPaas.Vault] do
  {:ok, _} = child.start_link()
end

webhook_host =
  System.get_env("PAAS_WEBHOOK_HOST") ||
    System.get_env("PHX_HOST") ||
    "paas.gestaobem.com"

Application.put_env(:phoenix_paas, PhoenixPaasWeb.Endpoint,
  server: false,
  url: [host: webhook_host, port: 443, scheme: "https"]
)

{:ok, _} = PhoenixPaasWeb.Endpoint.start_link()

alias PhoenixPaas.{Accounts, Apps, Repo, Servers}
import Ecto.Query

email = "matheus.puppe@gmail.com"
user = Accounts.get_user_by_email(email) || raise "user not found: #{email}"
scope = Accounts.ensure_scope_for_user(user)
tenant_id = scope.tenant.id

# DNS A record for decor.gestaobem.com (as of 2026-08)
host_ip = System.get_env("DECOR_SERVER_IP") || "52.73.89.19"
server_name = System.get_env("DECOR_SERVER_NAME") || "decor-lightsail"

ssh_key =
  case System.get_env("SEED_SSH_KEY_PATH") do
    path when is_binary(path) and path != "" ->
      if File.exists?(path), do: File.read!(path), else: nil

    _ ->
      default = Path.expand("~/.ssh/lightsail-default-key-us-east-1.pem")
      if File.exists?(default), do: File.read!(default), else: nil
  end

ssh_key =
  ssh_key ||
    case Repo.one(from s in Servers.Server, where: s.name == "gestaobem-cx33", limit: 1) do
      %Servers.Server{ssh_private_key_encrypted: key} when is_binary(key) and key != "" -> key
      _ -> nil
    end

server_attrs =
  %{
    name: server_name,
    host_ip: host_ip,
    ssh_user: "ubuntu",
    region: "us-east-1",
    deploy_mode: "shared",
    aws_instance_name: server_name
  }
  |> then(fn attrs ->
    if is_binary(ssh_key), do: Map.put(attrs, :ssh_private_key, ssh_key), else: attrs
  end)

server =
  case Repo.one(
         from s in Servers.Server,
           where: s.tenant_id == ^tenant_id and s.name == ^server_name,
           limit: 1
       ) do
    %Servers.Server{} = existing ->
      existing
      |> Servers.Server.changeset(server_attrs)
      |> Repo.update!()

    nil ->
      {:ok, server} = Servers.create_server(scope, server_attrs)
      server
  end

secret =
  System.get_env("DECOR_SECRET_KEY_BASE") ||
    Base.encode64(:crypto.strong_rand_bytes(48))

app_attrs = %{
  name: "Gestão Bem Decor",
  slug: "decor",
  github_repo: "gestao-bem/gestao-bem-decor",
  branch: "main",
  host: "decor.gestaobem.com",
  port: 4005,
  systemd_unit: "festa_platform",
  release_path: "/opt/festa_platform",
  auto_deploy: true,
  server_id: server.id
}

app =
  case Apps.get_app_by_repo("gestao-bem/gestao-bem-decor") do
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
  "PORT" => "4005",
  "PHX_HOST" => "decor.gestaobem.com",
  "POOL_SIZE" => "5",
  "SECRET_KEY_BASE" => secret,
  "DATABASE_PATH" => "/var/lib/festa_platform/festa_platform_prod.db",
  "PAY_CORE_MODE" => "production",
  "TURSO_DATABASE_URL" => System.get_env("DECOR_TURSO_DATABASE_URL"),
  "TURSO_AUTH_TOKEN" => System.get_env("DECOR_TURSO_AUTH_TOKEN")
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
    release_name: PhoenixPaas.Apps.App.release_name(app.slug),
    server: server.name,
    server_ip: server.host_ip,
    release_path: app.release_path,
    systemd_unit: app.systemd_unit,
    webhook: webhook_status,
    auto_deploy: app.auto_deploy,
    webhook_url: PhoenixPaas.Github.webhook_url()
  },
  label: "decor_setup"
)
