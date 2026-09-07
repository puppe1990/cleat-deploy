defmodule PhoenixPaas.Apps.RuntimeMemoryTest do
  use PhoenixPaas.DataCase, async: false

  alias PhoenixPaas.Apps.RuntimeMemory
  alias PhoenixPaas.TenancyFixtures

  setup do
    scope = TenancyFixtures.scope_fixture()
    server = TenancyFixtures.server_fixture(scope)
    %{scope: scope, server: server}
  end

  test "reads cgroup memory for a phoenix unit", %{scope: scope, server: server} do
    app =
      TenancyFixtures.app_fixture(scope, server, %{
        slug: "open-drive",
        systemd_unit: "open_drive",
        runtime: "phoenix"
      })

    assert %{bytes: 171_200_512, peak_bytes: 187_977_728, active?: true} =
             RuntimeMemory.for_app(app)

    assert RuntimeMemory.format(%{bytes: 171_200_512}) == "163 MB"
  end

  test "sums golang server and worker units", %{scope: scope, server: server} do
    app =
      TenancyFixtures.app_fixture(scope, server, %{
        slug: "github-projects",
        systemd_unit: "github-projects",
        runtime: "golang"
      })

    memory = RuntimeMemory.for_app(app)
    assert memory.bytes == 171_200_512 + 10_416_128
    assert memory.active?
    assert RuntimeMemory.format(memory) == "173 MB"
    assert RuntimeMemory.format_peak(memory) == "Peak 205 MB"
  end

  test "skips unsafe systemd unit names", %{scope: scope, server: server} do
    app =
      TenancyFixtures.app_fixture(scope, server, %{
        slug: "evil",
        systemd_unit: "atelie; rm -rf /"
      })

    assert RuntimeMemory.for_app(app) == nil
  end

  test "format_bytes uses one decimal under 10 MB" do
    assert RuntimeMemory.format_bytes(5_505_024) == "5.3 MB"
    assert RuntimeMemory.format_bytes(171_200_512) == "163 MB"
    assert RuntimeMemory.format(nil) == "—"
  end
end
