defmodule PhoenixPaas.Deploy.DnsTest do
  use ExUnit.Case, async: false

  alias PhoenixPaas.Deploy.Dns

  test "first_ipv4/1 returns an IPv4 host as-is without looking up DNS" do
    assert {:ok, "52.73.89.19"} = Dns.first_ipv4("52.73.89.19")
  end

  test "first_ipv4/1 returns the first A record from the resolver" do
    Application.put_env(:phoenix_paas, :dns_resolver, PhoenixPaas.Deploy.DnsMock)

    Mox.expect(PhoenixPaas.Deploy.DnsMock, :lookup_a, fn "app.gestaobem.com" ->
      {:ok, ["52.73.89.19", "1.2.3.4"]}
    end)

    assert {:ok, "52.73.89.19"} = Dns.first_ipv4("app.gestaobem.com")
  after
    Application.delete_env(:phoenix_paas, :dns_resolver)
  end

  test "first_ipv4/1 returns error when resolver has no A record" do
    Application.put_env(:phoenix_paas, :dns_resolver, PhoenixPaas.Deploy.DnsMock)

    Mox.expect(PhoenixPaas.Deploy.DnsMock, :lookup_a, fn "missing.example" ->
      {:error, :no_a_record}
    end)

    assert {:error, :no_a_record} = Dns.first_ipv4("missing.example")
  after
    Application.delete_env(:phoenix_paas, :dns_resolver)
  end

  test "ipv4_to_string/1 formats an inet A tuple" do
    assert Dns.ipv4_to_string({52, 73, 89, 19}) == "52.73.89.19"
  end
end
