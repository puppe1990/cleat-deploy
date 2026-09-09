defmodule CleatDeploy.Deploy.Dns do
  @moduledoc false

  def first_ipv4(host) when is_binary(host) do
    if ipv4?(host) do
      {:ok, host}
    else
      case resolver().lookup_a(host) do
        {:ok, [ip | _rest]} -> {:ok, ip}
        {:ok, []} -> {:error, :no_a_record}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def ipv4_to_string({a, b, c, d})
      when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d) do
    "#{a}.#{b}.#{c}.#{d}"
  end

  defp ipv4?(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, {_, _, _, _}} -> true
      _ -> false
    end
  end

  defp resolver do
    Application.get_env(:cleat_deploy, :dns_resolver, CleatDeploy.Deploy.DnsInet)
  end
end
