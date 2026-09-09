defmodule CleatDeploy.Deploy.DnsInet do
  @moduledoc false
  @behaviour CleatDeploy.Deploy.DnsResolver

  @impl true
  def lookup_a(host) when is_binary(host) do
    case :inet_res.lookup(String.to_charlist(host), :in, :a) do
      [] ->
        {:error, :no_a_record}

      addrs when is_list(addrs) ->
        {:ok, Enum.map(addrs, &CleatDeploy.Deploy.Dns.ipv4_to_string/1)}
    end
  end
end
