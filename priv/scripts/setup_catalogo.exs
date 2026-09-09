# Run on panel:
#   bin/cleat_deploy rpc "Code.eval_file('priv/scripts/setup_catalogo.exs')"
alias CleatDeploy.{Accounts, Apps, Deployments, Repo, Servers}
import Ecto.Query

email = "matheus.puppe@gmail.com"
user = Accounts.get_user_by_email(email) || raise "user not found: #{email}"
scope = Accounts.ensure_scope_for_user(user)
tenant_id = scope.tenant.id

host_ip = System.get_env("CATALOGO_SERVER_IP") || "52.73.89.19"

ssh_key =
  case System.get_env("SEED_SSH_KEY_PATH") do
    path when is_binary(path) and path != "" ->
      if File.exists?(path), do: File.read!(path), else: nil

    _ ->
      nil
  end

ssh_key =
  ssh_key ||
    case Repo.one(from s in Servers.Server, where: s.name == "trip-lightsail", limit: 1) do
      %Servers.Server{ssh_private_key_encrypted: key} when is_binary(key) and key != "" -> key
      _ -> nil
    end

server_attrs =
  %{
    name: "catalogo-lightsail",
    host_ip: host_ip,
    ssh_user: "ubuntu",
    region: "us-east-1",
    deploy_mode: "dedicated",
    aws_instance_name: "catalogo-lightsail"
  }
  |> then(fn attrs ->
    if is_binary(ssh_key), do: Map.put(attrs, :ssh_private_key, ssh_key), else: attrs
  end)

server =
  case Repo.one(
         from s in Servers.Server,
           where: s.tenant_id == ^tenant_id and s.name == "catalogo-lightsail",
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

app_attrs = %{
  name: "Catálogo",
  slug: "catalogo",
  github_repo: "gestao-bem/catalog_platform",
  branch: "main",
  host: "loja.gestaobem.com",
  port: 4000,
  systemd_unit: "catalog_platform",
  release_path: "/opt/catalog_platform",
  server_id: server.id
}

app =
  case Apps.get_app_by_repo("gestao-bem/catalog_platform") do
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
  "PORT" => "4000",
  "PHX_HOST" => "loja.gestaobem.com",
  "PLATFORM_HOSTS" => "loja.gestaobem.com",
  "DOMAIN_CNAME_TARGET" => "loja.gestaobem.com",
  "POOL_SIZE" => "10",
  "SECRET_KEY_BASE" => System.get_env("CATALOGO_SECRET_KEY_BASE"),
  "TURSO_DATABASE_URL" => System.get_env("CATALOGO_TURSO_DATABASE_URL"),
  "TURSO_AUTH_TOKEN" => System.get_env("CATALOGO_TURSO_AUTH_TOKEN"),
  "S3_BUCKET" => System.get_env("CATALOGO_S3_BUCKET") || "loja-gestaobem-prod-840298254452",
  "AWS_ACCESS_KEY_ID" =>
    System.get_env("CATALOGO_AWS_ACCESS_KEY_ID") || System.get_env("AWS_ACCESS_KEY_ID"),
  "AWS_SECRET_ACCESS_KEY" =>
    System.get_env("CATALOGO_AWS_SECRET_ACCESS_KEY") || System.get_env("AWS_SECRET_ACCESS_KEY"),
  "AWS_REGION" => System.get_env("CATALOGO_AWS_REGION") || System.get_env("AWS_REGION") || "us-east-1"
}

for {key, value} <- env, is_binary(value) and value != "" do
  {:ok, _} = Apps.put_env_var(app, key, value)
end

{status, _} = Apps.sync_github_webhook(app)

{:ok, deployment} =
  Deployments.enqueue(scope, app, %{git_sha: "setup-catalogo", triggered_by: "manual"})

IO.inspect(%{
  app_id: app.id,
  slug: app.slug,
  host: app.host,
  server_ip: server.host_ip,
  webhook: status,
  deployment_id: deployment.id
}, label: "catalogo_setup")