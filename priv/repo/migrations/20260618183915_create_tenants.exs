defmodule CleatDeploy.Repo.Migrations.CreateTenants do
  use Ecto.Migration

  def change do
    create table(:tenants) do
      add :name, :string, null: false
      add :slug, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tenants, [:slug])

    create table(:tenant_memberships) do
      add :role, :string, null: false, default: "owner"
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :tenant_id, references(:tenants, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tenant_memberships, [:user_id, :tenant_id])
    create index(:tenant_memberships, [:tenant_id])
  end
end
