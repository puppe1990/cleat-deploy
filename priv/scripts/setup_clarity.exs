# Register CLARITY AI (puppe1990/assistente-ia) on catalogo-lightsail.
#
#   GITHUB_TOKEN=... XAI_API_KEY=... \
#     mix run --no-start priv/scripts/setup_clarity.exs

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

alias CleatDeploy.{Accounts, Apps, Repo, Servers}
import Ecto.Query

email = "matheus.puppe@gmail.com"
user = Accounts.get_user_by_email(email) || raise "user not found: #{email}"
scope = Accounts.ensure_scope_for_user(user)
tenant_id = scope.tenant.id

host_ip = System.get_env("CLARITY_SERVER_IP") || "52.73.89.19"
server_name = System.get_env("CLARITY_SERVER_NAME") || "catalogo-lightsail"
host = System.get_env("CLARITY_HOST") || "clarity.gestaobem.com"
port = String.to_integer(System.get_env("CLARITY_PORT") || "4013")

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
    case Repo.one(from s in Servers.Server, where: s.name == ^server_name, limit: 1) do
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
  System.get_env("CLARITY_SECRET_KEY_BASE") ||
    Base.encode64(:crypto.strong_rand_bytes(48))

app_attrs = %{
  name: "CLARITY AI",
  slug: "assistente",
  github_repo: "puppe1990/assistente-ia",
  branch: "main",
  host: host,
  port: port,
  systemd_unit: "assistente",
  release_path: "/opt/assistente",
  auto_deploy: true,
  server_id: server.id
}

app =
  case Apps.get_app_by_repo("puppe1990/assistente-ia") do
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
  "PORT" => Integer.to_string(port),
  "PHX_HOST" => host,
  "POOL_SIZE" => "5",
  "SECRET_KEY_BASE" => secret,
  "DATABASE_PATH" => "/var/lib/assistente/replica.db",
  "XAI_API_KEY" => System.get_env("XAI_API_KEY")
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
    release_name: CleatDeploy.Apps.App.release_name(app.slug),
    server: server.name,
    server_ip: server.host_ip,
    release_path: app.release_path,
    systemd_unit: app.systemd_unit,
    webhook: webhook_status,
    xai_key: if(System.get_env("XAI_API_KEY") in [nil, ""], do: :missing, else: :set)
  },
  label: "clarity_setup"
)
