# Register the Hetzner CX33 in the panel and point Lightsail Phoenix/Go apps at it.
#
#   HETZNER_SERVER_IP=x.x.x.x bin/phoenix_paas rpc "Code.eval_file(\"priv/scripts/setup_hetzner.exs\")"

alias PhoenixPaas.{Accounts, Apps, Repo, Servers}
import Ecto.Query

email = "matheus.puppe@gmail.com"
user = Accounts.get_user_by_email(email) || raise "user not found: #{email}"
scope = Accounts.ensure_scope_for_user(user)
tenant_id = scope.tenant.id

host_ip = System.get_env("HETZNER_SERVER_IP") || raise "HETZNER_SERVER_IP is required"
region = System.get_env("HETZNER_LOCATION") || "fsn1"

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
    case Repo.one(from s in Servers.Server, where: s.name == "catalogo-lightsail", limit: 1) do
      %Servers.Server{ssh_private_key_encrypted: key} when is_binary(key) and key != "" -> key
      _ -> nil
    end

server_attrs =
  %{
    name: "gestaobem-cx33",
    host_ip: host_ip,
    ssh_user: "ubuntu",
    region: region,
    provider: "hetzner",
    deploy_mode: "shared",
    aws_instance_name: "gestaobem-cx33",
    bundle_id: "cx33",
    bundle_name: "CX33",
    cpu_count: 4,
    ram_mb: 8192,
    disk_gb: 80,
    instance_status: "running"
  }
  |> then(fn attrs ->
    if is_binary(ssh_key), do: Map.put(attrs, :ssh_private_key, ssh_key), else: attrs
  end)

server =
  case Repo.one(
         from s in Servers.Server,
           where: s.tenant_id == ^tenant_id and s.name == "gestaobem-cx33",
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

golang_apps = [
  %{
    name: "Ateliê",
    slug: "atelie",
    github_repo: "puppe1990/atelie",
    host: "atelie.gestaobem.com",
    port: 4020,
    runtime: "golang",
    systemd_unit: "atelie",
    release_path: "/opt/atelie"
  },
  %{
    name: "Leilão ERP",
    slug: "leilao-erp",
    github_repo: "puppe1990/leilao-erp",
    host: "eletronicos.gestaobem.com",
    port: 8080,
    runtime: "golang",
    systemd_unit: "leilao-erp",
    release_path: "/opt/leilao-erp"
  },
  %{
    name: "Trama Brás",
    slug: "trama-bras",
    github_repo: "puppe1990/trama-bras",
    host: "trama.gestaobem.com",
    port: 4006,
    runtime: "golang",
    systemd_unit: "trama-bras",
    release_path: "/opt/trama-bras"
  },
  %{
    name: "GitHub Projects",
    slug: "github-projects",
    github_repo: "puppe1990/github-projects-viewer-cais",
    host: "github.gestaobem.com",
    port: 4021,
    runtime: "golang",
    systemd_unit: "github-projects",
    release_path: "/opt/github-projects"
  }
]

for attrs <- golang_apps do
  app_attrs = Map.put(attrs, :server_id, server.id)

  case Apps.get_app_by_repo(attrs.github_repo) do
    nil ->
      {:ok, _app, _status} = Apps.create_app(scope, app_attrs)

    %{} = existing ->
      existing
      |> Ecto.Changeset.change(Map.put(app_attrs, :tenant_id, tenant_id))
      |> Repo.update!()
  end
end

reassign_slugs = [
  "catalogo",
  "vexo",
  "assistente",
  "decor",
  "open-drive",
  "pay-core",
  "phoenix-paas"
]

updated =
  Repo.all(from a in Apps.App, where: a.tenant_id == ^tenant_id and a.slug in ^reassign_slugs)
  |> Enum.map(fn app ->
    app
    |> Ecto.Changeset.change(%{server_id: server.id})
    |> Repo.update!()

    app.slug
  end)

IO.inspect(
  %{
    server_id: server.id,
    server_ip: server.host_ip,
    provider: server.provider,
    reassigned: updated
  },
  label: "hetzner_setup"
)
