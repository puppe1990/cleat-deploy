alias CleatDeploy.{Apps, Repo}
alias CleatDeploy.Apps.App

app = Repo.get_by!(App, slug: "open-drive")

secrets = %{
  "SECRET_KEY_BASE" => System.get_env("OPEN_DRIVE_SECRET_KEY_BASE"),
  "TURSO_DATABASE_URL" => System.get_env("OPEN_DRIVE_TURSO_DATABASE_URL"),
  "TURSO_AUTH_TOKEN" => System.get_env("OPEN_DRIVE_TURSO_AUTH_TOKEN"),
  "AWS_S3_BUCKET" => System.get_env("AWS_S3_BUCKET"),
  "AWS_REGION" => System.get_env("AWS_REGION"),
  "AWS_ACCESS_KEY_ID" => System.get_env("AWS_ACCESS_KEY_ID"),
  "AWS_SECRET_ACCESS_KEY" => System.get_env("AWS_SECRET_ACCESS_KEY")
}

for {key, value} <- secrets, is_binary(value) and value != "" do
  {:ok, _} = Apps.put_env_var(app, key, value)
end

content = Apps.env_map(Apps.get_app!(app.id))
IO.puts("synced keys: #{Map.keys(content) |> Enum.sort() |> Enum.join(", ")}")