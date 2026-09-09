defmodule CleatDeploy.Repo.Migrations.AddInstanceSpecsToServers do
  use Ecto.Migration

  def change do
    alter table(:servers) do
      add :bundle_id, :string
      add :bundle_name, :string
      add :cpu_count, :integer
      add :ram_mb, :integer
      add :disk_gb, :integer
      add :instance_status, :string
      add :blueprint_name, :string
      add :monthly_price_usd, :decimal
      add :specs_synced_at, :utc_datetime
    end
  end
end
