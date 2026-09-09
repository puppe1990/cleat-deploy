defmodule CleatDeploy.Repo.Migrations.AddProviderAndRuntime do
  use Ecto.Migration

  def change do
    alter table(:servers) do
      add :provider, :string, null: false, default: "lightsail"
    end

    alter table(:apps) do
      add :runtime, :string, null: false, default: "phoenix"
    end
  end
end
