defmodule CleatDeployWeb.ServerLiveShowTest do
  use CleatDeployWeb.ConnCase, async: false

  import Mox
  import Phoenix.LiveViewTest

  alias CleatDeploy.AWS.Lightsail.Catalog
  alias CleatDeploy.AWS.Lightsail.InstanceSpec
  alias CleatDeploy.AWS.LightsailMock
  alias CleatDeploy.TenancyFixtures

  setup :verify_on_exit!

  setup :register_and_log_in_user

  setup do
    stub(LightsailMock, :list_bundles, fn _region -> {:ok, Catalog.all_bundles()} end)
    :ok
  end

  test "shows machine specs on server detail page", %{conn: conn, scope: scope} do
    server =
      TenancyFixtures.server_fixture(scope, %{
        name: "prod-lightsail",
        aws_instance_name: "trip-lightsail",
        bundle_id: "nano_3_0",
        bundle_name: "Nano",
        cpu_count: 2,
        ram_mb: 512,
        disk_gb: 20,
        instance_status: "running",
        blueprint_name: "Ubuntu"
      })

    {:ok, view, html} = live(conn, ~p"/servers/#{server.id}")

    assert html =~ "prod-lightsail"
    assert has_element?(view, "#server-specs")
    assert render(view) =~ "Nano"
    assert render(view) =~ "512 MB"
    assert render(view) =~ "20 GB"
  end

  test "sync specs button refreshes machine info", %{conn: conn, scope: scope} do
    server =
      TenancyFixtures.server_fixture(scope, %{
        aws_instance_name: "trip-lightsail",
        region: "us-east-1"
      })

    spec = %InstanceSpec{
      bundle_id: "micro_3_0",
      bundle_name: "Micro",
      cpu_count: 2,
      ram_mb: 1024,
      disk_gb: 40,
      status: "running",
      blueprint_name: "Ubuntu",
      monthly_price_usd: Decimal.new("7.00")
    }

    expect(LightsailMock, :get_instance, fn "us-east-1", "trip-lightsail" ->
      {:ok, spec}
    end)

    {:ok, view, _html} = live(conn, ~p"/servers/#{server.id}")

    view |> element("#sync-specs-button") |> render_click()

    assert render(view) =~ "Micro"
    assert render(view) =~ "1 GB"
  end

  test "resize bundle upgrades instance plan", %{conn: conn, scope: scope} do
    server =
      TenancyFixtures.server_fixture(scope, %{
        aws_instance_name: "trip-lightsail",
        region: "us-east-1",
        bundle_id: "nano_3_0",
        bundle_name: "Nano",
        cpu_count: 2,
        ram_mb: 512,
        disk_gb: 20
      })

    upgraded = %InstanceSpec{
      bundle_id: "micro_3_0",
      bundle_name: "Micro",
      cpu_count: 2,
      ram_mb: 1024,
      disk_gb: 40,
      status: "running",
      blueprint_name: "Ubuntu",
      monthly_price_usd: Decimal.new("7.00")
    }

    expect(LightsailMock, :change_bundle, fn "us-east-1", "trip-lightsail", "micro_3_0" -> :ok end)

    expect(LightsailMock, :get_instance, fn "us-east-1", "trip-lightsail" -> {:ok, upgraded} end)

    {:ok, view, _html} = live(conn, ~p"/servers/#{server.id}")

    view
    |> element("#resize-bundle-form")
    |> render_change(%{"bundle_id" => "micro_3_0"})

    view |> element("#resize-bundle-button") |> render_click()

    assert render(view) =~ "Micro"
    assert render(view) =~ "Instance plan updated"
  end
end
