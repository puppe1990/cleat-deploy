defmodule CleatDeploy.AWS.Lightsail.Catalog do
  @moduledoc false

  alias CleatDeploy.AWS.Lightsail.Bundle

  @bundles [
    %{
      bundle_id: "nano_3_0",
      bundle_name: "Nano",
      cpu_count: 2,
      ram_mb: 512,
      disk_gb: 20,
      monthly_price_usd: Decimal.new("5.00")
    },
    %{
      bundle_id: "micro_3_0",
      bundle_name: "Micro",
      cpu_count: 2,
      ram_mb: 1024,
      disk_gb: 40,
      monthly_price_usd: Decimal.new("7.00")
    },
    %{
      bundle_id: "small_3_0",
      bundle_name: "Small",
      cpu_count: 2,
      ram_mb: 2048,
      disk_gb: 60,
      monthly_price_usd: Decimal.new("12.00")
    },
    %{
      bundle_id: "medium_3_0",
      bundle_name: "Medium",
      cpu_count: 2,
      ram_mb: 4096,
      disk_gb: 80,
      monthly_price_usd: Decimal.new("24.00")
    },
    %{
      bundle_id: "large_3_0",
      bundle_name: "Large",
      cpu_count: 2,
      ram_mb: 8192,
      disk_gb: 160,
      monthly_price_usd: Decimal.new("44.00")
    },
    %{
      bundle_id: "xlarge_3_0",
      bundle_name: "Xlarge",
      cpu_count: 4,
      ram_mb: 16_384,
      disk_gb: 320,
      monthly_price_usd: Decimal.new("84.00")
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
