defmodule CleatDeploy.Repo.Migrations.AddDeployModeToServers do
  use Ecto.Migration

  def change do
    alter table(:servers) do
      add :deploy_mode, :string, null: false, default: "shared"
    end
  end
end
