defmodule CleatDeploy.ServersSpecsTest do
  use CleatDeploy.DataCase

  import Mox

  alias CleatDeploy.AWS.Lightsail.{Bundle, InstanceSpec}
  alias CleatDeploy.AWS.LightsailMock
  alias CleatDeploy.Servers
  alias CleatDeploy.TenancyFixtures

  setup :verify_on_exit!

  setup do
    %{scope: TenancyFixtures.scope_fixture()}
  end

  describe "sync_specs/2" do
    test "updates server with Lightsail instance specs", %{scope: scope} do
      server =
        TenancyFixtures.server_fixture(scope, %{
          aws_instance_name: "trip-lightsail",
          region: "us-east-1"
        })

      spec = %InstanceSpec{
        bundle_id: "nano_3_0",
        bundle_name: "Nano",
        cpu_count: 2,
        ram_mb: 512,
        disk_gb: 20,
        status: "running",
        blueprint_name: "Ubuntu",
        monthly_price_usd: Decimal.new("5.00")
      }

      expect(LightsailMock, :get_instance, fn "us-east-1", "trip-lightsail" ->
        {:ok, spec}
      end)

      assert {:ok, updated} = Servers.sync_specs(scope, server)
      assert updated.bundle_id == "nano_3_0"
      assert updated.bundle_name == "Nano"
      assert updated.cpu_count == 2
      assert updated.ram_mb == 512
      assert updated.disk_gb == 20
      assert updated.instance_status == "running"
      assert updated.blueprint_name == "Ubuntu"
      assert updated.specs_synced_at
    end

    test "returns error when aws_instance_name is missing", %{scope: scope} do
      server = TenancyFixtures.server_fixture(scope, %{aws_instance_name: nil})

      assert {:error, :missing_instance_name} = Servers.sync_specs(scope, server)
    end

    test "marks the server missing when Lightsail no longer has the VM", %{scope: scope} do
      server =
        TenancyFixtures.server_fixture(scope, %{
          aws_instance_name: "missing-vm",
          region: "us-east-1"
        })

      expect(LightsailMock, :get_instance, fn _, _ ->
        {:error, :not_found}
      end)

      assert {:ok, updated} = Servers.sync_specs(scope, server)
      assert updated.instance_status == "missing"
    end
  end

  describe "list_resize_options/2" do
    test "returns bundles excluding current plan", %{scope: scope} do
      server =
        TenancyFixtures.server_fixture(scope, %{
          aws_instance_name: "trip-lightsail",
          region: "us-east-1",
          bundle_id: "nano_3_0"
        })

      bundles = [
        %Bundle{
          bundle_id: "nano_3_0",
          bundle_name: "Nano",
          cpu_count: 2,
          ram_mb: 512,
          disk_gb: 20,
          monthly_price_usd: Decimal.new("5.00")
        },
        %Bundle{
          bundle_id: "micro_3_0",
          bundle_name: "Micro",
          cpu_count: 2,
          ram_mb: 1024,
          disk_gb: 40,
          monthly_price_usd: Decimal.new("7.00")
        }
      ]

      expect(LightsailMock, :list_bundles, fn "us-east-1" -> {:ok, bundles} end)

      assert options = Servers.list_resize_options(scope, server)
      assert Enum.map(options, & &1.bundle_id) == ["micro_3_0"]
    end
  end

  describe "resize_bundle/3" do
    test "changes bundle and refreshes specs", %{scope: scope} do
      server =
        TenancyFixtures.server_fixture(scope, %{
          aws_instance_name: "trip-lightsail",
          region: "us-east-1",
          bundle_id: "nano_3_0"
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

      expect(LightsailMock, :change_bundle, fn "us-east-1", "trip-lightsail", "micro_3_0" ->
        :ok
      end)

      expect(LightsailMock, :get_instance, fn "us-east-1", "trip-lightsail" ->
        {:ok, upgraded}
      end)

      assert {:ok, updated} = Servers.resize_bundle(scope, server, "micro_3_0")
      assert updated.bundle_id == "micro_3_0"
      assert updated.ram_mb == 1024
    end

    test "returns error when resize API fails", %{scope: scope} do
      server =
        TenancyFixtures.server_fixture(scope, %{
          aws_instance_name: "trip-lightsail",
          region: "us-east-1"
        })

      expect(LightsailMock, :change_bundle, fn _, _, _ ->
        {:error, :invalid_bundle}
      end)

      assert {:error, :invalid_bundle} = Servers.resize_bundle(scope, server, "xlarge_3_0")
    end
  end

  describe "delete_server/2" do
    test "deletes a server with no apps", %{scope: scope} do
      server = TenancyFixtures.server_fixture(scope, %{name: "gone-box"})

      assert {:ok, _} = Servers.delete_server(scope, server)
      assert Servers.list_servers(scope) == []
    end

    test "refuses to delete a server that still has apps", %{scope: scope} do
      server = TenancyFixtures.server_fixture(scope)
      TenancyFixtures.app_fixture(scope, server)

      assert {:error, :has_apps} = Servers.delete_server(scope, server)
      assert [%{id: id}] = Servers.list_servers(scope)
      assert id == server.id
    end
  end
end
