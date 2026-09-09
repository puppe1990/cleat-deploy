defmodule CleatDeploy.Repo.Migrations.CreateApps do
  use Ecto.Migration

  def change do
    create table(:apps) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :github_repo, :string, null: false
      add :branch, :string, null: false, default: "main"
      add :host, :string, null: false
      add :port, :integer, null: false, default: 4000
      add :systemd_unit, :string
      add :release_path, :string
      add :webhook_secret, :string
      add :auto_deploy, :boolean, null: false, default: true
      add :server_id, references(:servers, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:apps, [:slug])
    create unique_index(:apps, [:github_repo])
    create index(:apps, [:server_id])

    create table(:app_env_vars) do
      add :key, :string, null: false
      add :value, :binary, null: false
      add :app_id, references(:apps, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:app_env_vars, [:app_id, :key])
  end
end
