defmodule CleatDeploy.AWS.Lightsail.Bundle do
  @moduledoc false

  @enforce_keys [
    :bundle_id,
    :bundle_name,
    :cpu_count,
    :ram_mb,
    :disk_gb,
    :monthly_price_usd
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          bundle_id: String.t(),
          bundle_name: String.t(),
          cpu_count: pos_integer(),
          ram_mb: pos_integer(),
          disk_gb: pos_integer(),
          monthly_price_usd: Decimal.t()
        }

  def format_price(%__MODULE__{monthly_price_usd: price}) do
    "$#{Decimal.round(price, 2)}/mo"
  end
end
