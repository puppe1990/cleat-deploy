defmodule CleatDeploy.Repo.Migrations.CreateServers do
  use Ecto.Migration

  def change do
    create table(:servers) do
      add :name, :string, null: false
      add :host_ip, :string, null: false
      add :ssh_user, :string, null: false, default: "ubuntu"
      add :region, :string, null: false, default: "us-east-1"
      add :ssh_private_key_encrypted, :binary
      add :aws_instance_name, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:servers, [:name])
  end
end
