# Register Vexo on the shared Lightsail host (catalogo-lightsail @ 52.73.89.19).
#
# On production panel:
#   bin/cleat_deploy rpc "Code.eval_file(\"/tmp/setup_vexo.exs\")"

alias CleatDeploy.{Accounts, Apps, Deployments, Repo, Servers}
import Ecto.Query

email = "matheus.puppe@gmail.com"
user = Accounts.get_user_by_email(email) || raise "user not found: #{email}"
scope = Accounts.ensure_scope_for_user(user)
tenant_id = scope.tenant.id

server =
  Repo.one!(
    from s in Servers.Server,
      where: s.tenant_id == ^tenant_id and s.name == "catalogo-lightsail",
      limit: 1
  )

app_attrs = %{
  name: "Vexo",
  slug: "vexo",
  github_repo: "puppe1990/vexo",
  branch: "main",
  host: "vexo.gestaobem.com",
  port: 4012,
  systemd_unit: "vexo",
  release_path: "/opt/vexo",
  auto_deploy: true,
  server_id: server.id
}

app =
  case Apps.get_app_by_repo("puppe1990/vexo") do
    nil ->
      {:ok, app, _status} = Apps.create_app(scope, app_attrs)
      Apps.get_app!(scope, app.id)

    %{} = existing ->
      existing
      |> Ecto.Changeset.change(Map.put(app_attrs, :tenant_id, tenant_id))
      |> Repo.update!()
  end

env_path = "/etc/vexo/env"

if File.exists?(env_path) do
  env_path
  |> File.read!()
  |> String.split("\n")
  |> Enum.each(fn line ->
    line = String.trim(line)

    cond do
      line == "" ->
        :ok

      String.starts_with?(line, "#") ->
        :ok

      true ->
        line = String.replace_prefix(line, "export ", "")

        case String.split(line, "=", parts: 2) do
          [key, value] ->
            value = value |> String.trim() |> String.trim("\"") |> String.trim("'")
            {:ok, _} = Apps.put_env_var(app, key, value)

          _ ->
            :ok
        end
    end
  end)
end

{webhook_status, _} = Apps.sync_github_webhook(app)

git_sha = System.get_env("VEXO_GIT_SHA") || "29c42659bfd2b6a067fea547db621d7b9fdb2fd1"

{:ok, job} =
  Deployments.enqueue(scope, app, %{
    git_sha: git_sha,
    git_ref: "main",
    triggered_by: "manual"
  })

IO.inspect(
  %{
    app_id: app.id,
    slug: app.slug,
    host: app.host,
    port: app.port,
    release_name: CleatDeploy.Apps.App.release_name(app.slug),
    server: server.name,
    server_ip: server.host_ip,
    webhook: webhook_status,
    auto_deploy: app.auto_deploy,
    job_id: job.id,
    git_sha: git_sha
  },
  label: "vexo_setup"
)
