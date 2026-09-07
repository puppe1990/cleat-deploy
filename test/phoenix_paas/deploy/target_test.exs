defmodule PhoenixPaas.Deploy.TargetTest do
  use PhoenixPaas.DataCase, async: false

  import Mox

  alias PhoenixPaas.Deploy.Target
  alias PhoenixPaas.TenancyFixtures

  setup :verify_on_exit!

  setup do
    previous = Application.get_env(:phoenix_paas, :dns_resolver)
    Application.put_env(:phoenix_paas, :dns_resolver, PhoenixPaas.Deploy.DnsMock)

    on_exit(fn ->
      if previous do
        Application.put_env(:phoenix_paas, :dns_resolver, previous)
      else
        Application.delete_env(:phoenix_paas, :dns_resolver)
      end
    end)

    scope = TenancyFixtures.scope_fixture()
    %{scope: scope}
  end

  test "ssh_host_ip/2 uses the DNS A record when it differs from the stored IP", %{scope: scope} do
    server = TenancyFixtures.server_fixture(scope, %{host_ip: "52.0.157.89"})
    app = TenancyFixtures.app_fixture(scope, server, %{host: "app.gestaobem.com"})

    expect(PhoenixPaas.Deploy.DnsMock, :lookup_a, fn "app.gestaobem.com" ->
      {:ok, ["52.73.89.19"]}
    end)

    assert Target.ssh_host_ip(app, server) == "52.73.89.19"
  end

  test "ssh_host_ip/2 falls back to the stored server IP when DNS fails", %{scope: scope} do
    server = TenancyFixtures.server_fixture(scope, %{host_ip: "10.0.0.9"})
    app = TenancyFixtures.app_fixture(scope, server, %{host: "offline.example"})

    expect(PhoenixPaas.Deploy.DnsMock, :lookup_a, fn "offline.example" ->
      {:error, :no_a_record}
    end)

    assert Target.ssh_host_ip(app, server) == "10.0.0.9"
  end

  test "sync_server_host_ip/2 persists when DNS IP differs and no apps conflict", %{scope: scope} do
    server = TenancyFixtures.server_fixture(scope, %{host_ip: "52.0.157.89"})
    _app = TenancyFixtures.app_fixture(scope, server, %{host: "app.gestaobem.com"})

    expect(PhoenixPaas.Deploy.DnsMock, :lookup_a, fn "app.gestaobem.com" ->
      {:ok, ["52.73.89.19"]}
    end)

    assert {:ok, updated} = Target.sync_server_host_ip(server, "52.73.89.19")
    assert updated.host_ip == "52.73.89.19"
  end

  test "reconcile_server_ips/0 updates a server when every app host points at one IP", %{
    scope: scope
  } do
    server = TenancyFixtures.server_fixture(scope, %{name: "stale-vm", host_ip: "52.0.157.89"})

    TenancyFixtures.app_fixture(scope, server, %{
      host: "app.gestaobem.com",
      github_repo: "owner/app-#{System.unique_integer()}"
    })

    expect(PhoenixPaas.Deploy.DnsMock, :lookup_a, fn "app.gestaobem.com" ->
      {:ok, ["52.73.89.19"]}
    end)

    results = Target.reconcile_server_ips()
    assert {"stale-vm", {:updated, "52.73.89.19"}} in results

    reloaded = PhoenixPaas.Servers.get_server!(scope, server.id)
    assert reloaded.host_ip == "52.73.89.19"
  end

  test "reconcile_server_ips/0 does not change a shared server when app hosts disagree", %{
    scope: scope
  } do
    server = TenancyFixtures.server_fixture(scope, %{name: "shared-vm", host_ip: "10.0.0.1"})

    TenancyFixtures.app_fixture(scope, server, %{
      host: "app-a.example",
      github_repo: "owner/a-#{System.unique_integer()}"
    })

    TenancyFixtures.app_fixture(scope, server, %{
      host: "app-b.example",
      github_repo: "owner/b-#{System.unique_integer()}"
    })

    stub(PhoenixPaas.Deploy.DnsMock, :lookup_a, fn
      "app-a.example" -> {:ok, ["1.1.1.1"]}
      "app-b.example" -> {:ok, ["2.2.2.2"]}
    end)

    results = Target.reconcile_server_ips()
    assert {"shared-vm", {:conflict, _ips}} = Enum.find(results, &(elem(&1, 0) == "shared-vm"))

    reloaded = PhoenixPaas.Servers.get_server!(scope, server.id)
    assert reloaded.host_ip == "10.0.0.1"
  end
end
