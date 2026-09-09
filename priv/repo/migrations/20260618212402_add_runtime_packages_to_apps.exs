defmodule CleatDeploy.Repo.Migrations.AddRuntimePackagesToApps do
  use Ecto.Migration

  def change do
    alter table(:apps) do
      add :runtime_apt_packages, :json, null: false, default: "[]"
    end
  end
end
