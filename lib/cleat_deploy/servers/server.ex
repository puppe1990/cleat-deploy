defmodule CleatDeploy.Servers.Server do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias CleatDeploy.Accounts.Tenant
  alias CleatDeploy.Encrypted

  schema "servers" do
    field :name, :string
    field :host_ip, :string
    field :ssh_user, :string, default: "ubuntu"
    field :region, :string, default: "us-east-1"
    field :ssh_private_key_encrypted, Encrypted.Binary
    field :ssh_private_key, :string, virtual: true
    field :provider, :string, default: "lightsail"
    field :aws_instance_name, :string
    field :bundle_id, :string
    field :bundle_name, :string
    field :cpu_count, :integer
    field :ram_mb, :integer
    field :disk_gb, :integer
    field :instance_status, :string
    field :blueprint_name, :string
    field :monthly_price_usd, :decimal
    field :specs_synced_at, :utc_datetime
    field :deploy_mode, :string, default: "shared"

    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime)
  end

  def changeset(server, attrs) do
    server
    |> cast(attrs, [
      :name,
      :host_ip,
      :ssh_user,
      :region,
      :ssh_private_key,
      :provider,
      :aws_instance_name,
      :bundle_id,
      :bundle_name,
      :cpu_count,
      :ram_mb,
      :disk_gb,
      :instance_status,
      :blueprint_name,
      :monthly_price_usd,
      :specs_synced_at,
      :deploy_mode,
      :tenant_id
    ])
    |> validate_required([:name, :host_ip, :ssh_user, :region, :tenant_id])
    |> validate_inclusion(:deploy_mode, ["shared", "dedicated"])
    |> validate_inclusion(:provider, ["lightsail", "hetzner"])
    |> validate_length(:name, min: 1, max: 160)
    |> validate_ipv4(:host_ip)
    |> maybe_put_ssh_key()
    |> unique_constraint(:name, name: :servers_tenant_id_name_index)
  end

  defp maybe_put_ssh_key(changeset) do
    case get_change(changeset, :ssh_private_key) do
      key when is_binary(key) and key != "" ->
        changeset
        |> put_change(:ssh_private_key_encrypted, String.trim_trailing(key))
        |> delete_change(:ssh_private_key)

      _ ->
        delete_change(changeset, :ssh_private_key)
    end
  end

  def specs_configured?(%__MODULE__{} = server) do
    is_binary(server.bundle_id) and server.bundle_id != ""
  end

  def format_ram(%__MODULE__{ram_mb: ram_mb}) when is_integer(ram_mb) and ram_mb < 1024,
    do: "#{ram_mb} MB"

  def format_ram(%__MODULE__{ram_mb: ram_mb}) when is_integer(ram_mb) do
    gb = ram_mb / 1024
    if rem(ram_mb, 1024) == 0, do: "#{trunc(gb)} GB", else: "#{Float.round(gb, 1)} GB"
  end

  def format_ram(_), do: "—"

  def format_price(%__MODULE__{provider: "hetzner", monthly_price_usd: %Decimal{} = price}) do
    "€#{Decimal.round(price, 2)}/mo"
  end

  def format_price(%__MODULE__{monthly_price_usd: %Decimal{} = price}) do
    "$#{Decimal.round(price, 2)}/mo"
  end

  def format_price(_), do: "—"

  defp validate_ipv4(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      case :inet.parse_address(String.to_charlist(value)) do
        {:ok, {_, _, _, _}} -> []
        _ -> [{field, "is invalid"}]
      end
    end)
  end
end
