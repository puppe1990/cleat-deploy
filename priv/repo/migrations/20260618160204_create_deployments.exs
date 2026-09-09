defmodule CleatDeploy.Repo.Migrations.CreateDeployments do
  use Ecto.Migration

  def change do
    create table(:deployments) do
      add :git_sha, :string, null: false
      add :git_ref, :string
      add :status, :string, null: false, default: "queued"
      add :log, :text, null: false, default: ""
      add :triggered_by, :string, null: false, default: "manual"
      add :started_at, :utc_datetime
      add :finished_at, :utc_datetime
      add :app_id, references(:apps, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:deployments, [:app_id])
    create index(:deployments, [:status])
  end
end
