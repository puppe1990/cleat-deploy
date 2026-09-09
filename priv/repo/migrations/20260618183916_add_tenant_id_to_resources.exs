defmodule CleatDeploy.Repo.Migrations.AddTenantIdToResources do
  use Ecto.Migration

  def change do
    alter table(:servers) do
      add :tenant_id, references(:tenants, on_delete: :delete_all)
    end

    alter table(:apps) do
      add :tenant_id, references(:tenants, on_delete: :delete_all)
    end

    drop_if_exists unique_index(:servers, [:name])
    drop_if_exists unique_index(:apps, [:slug])
    drop_if_exists unique_index(:apps, [:github_repo])

    create index(:servers, [:tenant_id])
    create index(:apps, [:tenant_id])
    create unique_index(:servers, [:tenant_id, :name])
    create unique_index(:apps, [:tenant_id, :slug])
    create unique_index(:apps, [:tenant_id, :github_repo])
  end
end
