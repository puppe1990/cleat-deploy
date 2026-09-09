defmodule CleatDeploy.CloudTest do
  use CleatDeploy.DataCase

  import Mox

  alias CleatDeploy.AWS.Lightsail.{Bundle, InstanceSpec}
  alias CleatDeploy.AWS.LightsailMock
  alias CleatDeploy.Cloud
  alias CleatDeploy.HetznerMock
  alias CleatDeploy.TenancyFixtures

  setup :verify_on_exit!

  setup do
    %{scope: TenancyFixtures.scope_fixture()}
  end

  test "sync_specs uses the Hetzner client for hetzner servers", %{scope: scope} do
    server =
      TenancyFixtures.server_fixture(scope, %{
        provider: "hetzner",
        region: "fsn1",
        aws_instance_name: "gestaobem-cx33",
        ssh_user: "ubuntu"
      })

    spec = %InstanceSpec{
      bundle_id: "cx33",
      bundle_name: "CX33",
      cpu_count: 4,
      ram_mb: 8192,
      disk_gb: 80,
      status: "running",
      blueprint_name: "Ubuntu 24.04",
      monthly_price_usd: Decimal.new("7.59")
    }

    expect(HetznerMock, :get_instance, fn "fsn1", "gestaobem-cx33" -> {:ok, spec} end)

    assert {:ok, updated} = Cloud.sync_specs(server)
    assert updated.bundle_id == "cx33"
    assert updated.cpu_count == 4
    assert updated.ram_mb == 8192
  end

  test "list_resize_options uses Hetzner bundles for hetzner servers", %{scope: scope} do
    server =
      TenancyFixtures.server_fixture(scope, %{
        provider: "hetzner",
        region: "fsn1",
        aws_instance_name: "gestaobem-cx33",
        bundle_id: "cx33"
      })

    bundles = [
      %Bundle{
        bundle_id: "cx33",
        bundle_name: "CX33",
        cpu_count: 4,
        ram_mb: 8192,
        disk_gb: 80,
        monthly_price_usd: Decimal.new("7.59")
      },
      %Bundle{
        bundle_id: "cx43",
        bundle_name: "CX43",
        cpu_count: 8,
        ram_mb: 16_384,
        disk_gb: 160,
        monthly_price_usd: Decimal.new("13.59")
      }
    ]

    expect(HetznerMock, :list_bundles, fn "fsn1" -> {:ok, bundles} end)

    assert options = Cloud.list_resize_options(server)
    assert Enum.map(options, & &1.bundle_id) == ["cx43"]
  end

  test "resize_bundle uses the Hetzner client for hetzner servers", %{scope: scope} do
    server =
      TenancyFixtures.server_fixture(scope, %{
        provider: "hetzner",
        region: "fsn1",
        aws_instance_name: "gestaobem-cx33",
        bundle_id: "cx33"
      })

    upgraded = %InstanceSpec{
      bundle_id: "cx43",
      bundle_name: "CX43",
      cpu_count: 8,
      ram_mb: 16_384,
      disk_gb: 160,
      status: "running",
      blueprint_name: "Ubuntu 24.04",
      monthly_price_usd: Decimal.new("13.59")
    }

    expect(HetznerMock, :change_bundle, fn "fsn1", "gestaobem-cx33", "cx43" -> :ok end)
    expect(HetznerMock, :get_instance, fn "fsn1", "gestaobem-cx33" -> {:ok, upgraded} end)

    assert {:ok, updated} = Cloud.resize_bundle(server, "cx43")
    assert updated.bundle_id == "cx43"
    assert updated.ram_mb == 16_384
  end

  test "sync_specs still uses Lightsail for lightsail servers", %{scope: scope} do
    server =
      TenancyFixtures.server_fixture(scope, %{
        provider: "lightsail",
        region: "us-east-1",
        aws_instance_name: "catalogo-lightsail"
      })

    spec = %InstanceSpec{
      bundle_id: "small_3_0",
      bundle_name: "Small",
      cpu_count: 2,
      ram_mb: 2048,
      disk_gb: 60,
      status: "running",
      blueprint_name: "Ubuntu",
      monthly_price_usd: Decimal.new("12.00")
    }

    expect(LightsailMock, :get_instance, fn "us-east-1", "catalogo-lightsail" -> {:ok, spec} end)

    assert {:ok, updated} = Cloud.sync_specs(server)
    assert updated.bundle_id == "small_3_0"
  end

  test "sync_specs marks the server missing when the cloud VM is gone", %{scope: scope} do
    server =
      TenancyFixtures.server_fixture(scope, %{
        provider: "lightsail",
        region: "us-east-1",
        aws_instance_name: "catalogo-lightsail",
        instance_status: "running"
      })

    expect(LightsailMock, :get_instance, fn "us-east-1", "catalogo-lightsail" ->
      {:error, :not_found}
    end)

    assert {:ok, updated} = Cloud.sync_specs(server)
    assert updated.instance_status == "missing"
  end

  test "sync_inventory marks missing Lightsail VMs and keeps Tailscale private", %{scope: scope} do
    gone =
      TenancyFixtures.server_fixture(scope, %{
        name: "catalogo-lightsail",
        aws_instance_name: "catalogo-lightsail",
        host_ip: "52.73.89.19",
        provider: "lightsail",
        region: "us-east-1"
      })

    tailscale =
      TenancyFixtures.server_fixture(scope, %{
        name: "trip-lightsail",
        aws_instance_name: "trip-lightsail",
        host_ip: "100.59.80.29",
        provider: "lightsail",
        region: "us-east-1"
      })

    live =
      TenancyFixtures.server_fixture(scope, %{
        name: "gestaobem-cx33",
        aws_instance_name: "gestaobem-cx33",
        host_ip: "10.0.0.9",
        provider: "hetzner",
        region: "fsn1"
      })

    hetzner_spec =
      spec(%{
        name: "gestaobem-cx33",
        public_ip: "167.233.201.9",
        region: "fsn1",
        bundle_id: "cx33",
        bundle_name: "CX33",
        cpu_count: 4,
        ram_mb: 8192,
        disk_gb: 80,
        status: "running"
      })

    new_spec =
      spec(%{
        name: "fresh-box",
        public_ip: "167.233.201.10",
        region: "fsn1",
        bundle_id: "cx23",
        status: "running"
      })

    expect(LightsailMock, :list_instances, fn "us-east-1" -> {:ok, []} end)
    expect(HetznerMock, :list_instances, fn "fsn1" -> {:ok, [hetzner_spec, new_spec]} end)

    result = Cloud.sync_inventory([gone, tailscale, live])

    assert Enum.map(result.missing, & &1.id) == [gone.id]
    assert hd(result.missing).instance_status == "missing"

    assert Enum.map(result.private, & &1.id) == [tailscale.id]
    assert hd(result.private).instance_status == "private"

    assert [updated] = result.updated
    assert updated.id == live.id
    assert updated.instance_status == "running"
    assert updated.host_ip == "167.233.201.9"

    assert Enum.map(result.discovered, & &1.name) == ["fresh-box"]
  end

  defp spec(attrs) do
    struct(
      %InstanceSpec{
        bundle_id: "nano_3_0",
        bundle_name: "Nano",
        cpu_count: 2,
        ram_mb: 512,
        disk_gb: 20,
        status: "running",
        blueprint_name: "Ubuntu",
        monthly_price_usd: Decimal.new("5.00")
      },
      attrs
    )
  end
end
