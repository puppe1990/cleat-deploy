# Register GitHub Projects (puppe1990/github-projects-viewer-cais) on gestaobem-cx33.
#
# On the production panel:
#   bin/phoenix_paas rpc "Code.eval_file(\"priv/scripts/setup_github_projects.exs\")"

alias PhoenixPaas.{Accounts, Apps, Deployments, Repo, Servers}
import Ecto.Query

email = "matheus.puppe@gmail.com"
user = Accounts.get_user_by_email(email) || raise "user not found: #{email}"
scope = Accounts.ensure_scope_for_user(user)
tenant_id = scope.tenant.id

server_name = System.get_env("GITHUB_PROJECTS_SERVER_NAME") || "gestaobem-cx33"
host = System.get_env("GITHUB_PROJECTS_HOST") || "github.gestaobem.com"
port = String.to_integer(System.get_env("GITHUB_PROJECTS_PORT") || "4021")

server =
  Repo.one!(
    from s in Servers.Server,
      where: s.tenant_id == ^tenant_id and s.name == ^server_name,
      limit: 1
  )

app_attrs = %{
  name: "GitHub Projects",
  slug: "github-projects",
  github_repo: "puppe1990/github-projects-viewer-cais",
  branch: "main",
  host: host,
  port: port,
  runtime: "golang",
  systemd_unit: "github-projects",
  release_path: "/opt/github-projects",
  auto_deploy: true,
  server_id: server.id
}

app =
  case Apps.get_app_by_repo("puppe1990/github-projects-viewer-cais") do
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
admin_from_env = System.get_env("ADMIN_TOKEN")
admin_existing = Map.get(existing_env, "ADMIN_TOKEN")

admin_token =
  cond do
    is_binary(admin_from_env) and admin_from_env != "" -> admin_from_env
    is_binary(admin_existing) and admin_existing != "" -> admin_existing
    true -> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  end

env = %{
  "PORT" => ":#{port}",
  "ENV" => "production",
  "APP_URL" => "https://#{host}",
  "DB_PATH" => "/opt/github-projects/data/app.db",
  "LOCALE" => "pt",
  "TRUSTED_PROXIES" => "127.0.0.1",
  "STATIC_DIR" => "/opt/github-projects/current/web/static",
  "ADMIN_TOKEN" => admin_token,
  "GITHUB_TOKEN" => System.get_env("GITHUB_TOKEN"),
  "CSP_STYLE_SRC" => "https://fonts.googleapis.com",
  "CSP_FONT_SRC" => "https://fonts.gstatic.com",
  "CSP_IMG_SRC" => "https://avatars.githubusercontent.com"
}

for {key, value} <- env, is_binary(value) and value != "" do
  {:ok, _} = Apps.put_env_var(app, key, value)
end

{webhook_status, _} = Apps.sync_github_webhook(app)

git_sha = System.get_env("GITHUB_PROJECTS_GIT_SHA") || "manual"

{:ok, job} =
  Deployments.enqueue(scope, app, %{
    git_sha: git_sha,
    git_ref: app.branch || "main",
    triggered_by: "manual"
  })

IO.inspect(
  %{
    app_id: app.id,
    slug: app.slug,
    host: app.host,
    port: app.port,
    runtime: app.runtime,
    server: server.name,
    server_ip: server.host_ip,
    release_path: app.release_path,
    systemd_unit: app.systemd_unit,
    webhook: webhook_status,
    github_token: if(System.get_env("GITHUB_TOKEN") in [nil, ""], do: :missing, else: :set),
    admin_token: :set,
    deployment_job_id: job.id
  },
  label: "github_projects_setup"
)
