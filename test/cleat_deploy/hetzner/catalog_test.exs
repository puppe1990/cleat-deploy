defmodule CleatDeploy.Hetzner.CatalogTest do
  use ExUnit.Case, async: true

  alias CleatDeploy.Hetzner.Catalog

  test "cx33 is the 4 vCPU / 8 GB / 80 GB shared plan" do
    bundle = Catalog.find_bundle("cx33")

    assert bundle.bundle_id == "cx33"
    assert bundle.bundle_name == "CX33"
    assert bundle.cpu_count == 4
    assert bundle.ram_mb == 8192
    assert bundle.disk_gb == 80
    assert Decimal.eq?(bundle.monthly_price_usd, Decimal.new("7.59"))
  end

  test "all_bundles includes CX shared types" do
    ids = Catalog.all_bundles() |> Enum.map(& &1.bundle_id)
    assert "cx22" in ids
    assert "cx33" in ids
    assert "cx43" in ids
    assert "cx53" in ids
  end

  test "find_bundle returns nil for unknown types" do
    assert Catalog.find_bundle("nano_3_0") == nil
  end

  test "formats catalog prices in euro or converted dollar" do
    bundle = Catalog.find_bundle("cx33")

    assert Catalog.format_price(bundle, :eur) == "€7.59/mo"
    assert Catalog.format_price(bundle, :usd) == "$8.80/mo"
    assert Catalog.format_price(bundle) == "€7.59/mo"
  end
end
