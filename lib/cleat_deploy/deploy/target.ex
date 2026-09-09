defmodule CleatDeploy.Deploy.Target do
  @moduledoc false

  alias CleatDeploy.Apps
  alias CleatDeploy.Deploy.Dns
  alias CleatDeploy.Servers
  alias CleatDeploy.Servers.Server

  def ssh_host_ip(app, server) do
    case Dns.first_ipv4(app.host) do
      {:ok, ip} -> ip
      {:error, _reason} -> server.host_ip
    end
  end

  def sync_server_host_ip(%Server{} = server, ip) when is_binary(ip) do
    cond do
      server.host_ip == ip ->
        {:ok, server}

      conflicting_ips(server, ip) != [] ->
        {:ok, server}

      true ->
        Servers.update_host_ip(server, ip)
    end
  end

  def reconcile_server_ips do
    Apps.list_all_with_servers()
    |> Enum.group_by(& &1.server_id)
    |> Enum.map(fn {_server_id, apps} -> reconcile_group(apps) end)
  end

  defp reconcile_group([%{server: %Server{} = server} | _rest] = apps) do
    ips =
      apps
      |> Enum.flat_map(fn app ->
        case Dns.first_ipv4(app.host) do
          {:ok, ip} -> [ip]
          {:error, _} -> []
        end
      end)
      |> Enum.uniq()

    case ips do
      [] ->
        {server.name, :no_dns}

      [ip] when ip == server.host_ip ->
        {server.name, :ok}

      [ip] ->
        case Servers.update_host_ip(server, ip) do
          {:ok, _updated} -> {server.name, {:updated, ip}}
          {:error, reason} -> {server.name, {:error, reason}}
        end

      many ->
        {server.name, {:conflict, many}}
    end
  end

  defp conflicting_ips(%Server{id: server_id}, ip) do
    Apps.list_all_with_servers()
    |> Enum.filter(&(&1.server_id == server_id))
    |> Enum.flat_map(fn app ->
      case Dns.first_ipv4(app.host) do
        {:ok, resolved} when resolved != ip -> [resolved]
        _ -> []
      end
    end)
    |> Enum.uniq()
  end
end
