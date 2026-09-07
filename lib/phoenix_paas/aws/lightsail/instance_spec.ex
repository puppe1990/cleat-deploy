defmodule PhoenixPaas.AWS.Lightsail.InstanceSpec do
  @moduledoc false

  @enforce_keys [
    :bundle_id,
    :bundle_name,
    :cpu_count,
    :ram_mb,
    :disk_gb,
    :status,
    :blueprint_name,
    :monthly_price_usd
  ]
  defstruct @enforce_keys ++ [name: nil, public_ip: nil, region: nil]

  @type t :: %__MODULE__{
          bundle_id: String.t(),
          bundle_name: String.t(),
          cpu_count: pos_integer(),
          ram_mb: pos_integer(),
          disk_gb: pos_integer(),
          status: String.t(),
          blueprint_name: String.t(),
          monthly_price_usd: Decimal.t(),
          name: String.t() | nil,
          public_ip: String.t() | nil,
          region: String.t() | nil
        }

  def format_ram(%__MODULE__{ram_mb: ram_mb}) when ram_mb < 1024, do: "#{ram_mb} MB"

  def format_ram(%__MODULE__{ram_mb: ram_mb}) do
    gb = ram_mb / 1024
    if rem(ram_mb, 1024) == 0, do: "#{trunc(gb)} GB", else: "#{Float.round(gb, 1)} GB"
  end
end
