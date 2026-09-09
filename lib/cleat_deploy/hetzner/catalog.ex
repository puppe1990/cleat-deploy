defmodule CleatDeploy.Hetzner.Catalog do
  @moduledoc false

  alias CleatDeploy.AWS.Lightsail.Bundle

  # Shared x86 CX line. Prices are EUR stored in monthly_price_usd and
  # formatted with € for Hetzner servers.
  @bundles [
    %{
      bundle_id: "cx22",
      bundle_name: "CX22",
      cpu_count: 2,
      ram_mb: 4096,
      disk_gb: 40,
      monthly_price_usd: Decimal.new("4.59")
    },
    %{
      bundle_id: "cx33",
      bundle_name: "CX33",
      cpu_count: 4,
      ram_mb: 8192,
      disk_gb: 80,
      monthly_price_usd: Decimal.new("7.59")
    },
    %{
      bundle_id: "cx43",
      bundle_name: "CX43",
      cpu_count: 8,
      ram_mb: 16_384,
      disk_gb: 160,
      monthly_price_usd: Decimal.new("13.59")
    },
    %{
      bundle_id: "cx53",
      bundle_name: "CX53",
      cpu_count: 16,
      ram_mb: 32_768,
      disk_gb: 320,
      monthly_price_usd: Decimal.new("25.19")
    }
  ]

  def all_bundles do
    Enum.map(@bundles, &struct(Bundle, &1))
  end

  def find_bundle(bundle_id) when is_binary(bundle_id) do
    Enum.find(all_bundles(), &(&1.bundle_id == bundle_id))
  end

  def bundle_name(bundle_id) do
    case find_bundle(bundle_id) do
      %Bundle{bundle_name: name} -> name
      nil -> bundle_id
    end
  end
end
