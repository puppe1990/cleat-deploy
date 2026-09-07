defmodule PhoenixPaas.Apps.RuntimeLogsSsh do
  @moduledoc false
  @behaviour PhoenixPaas.Apps.RuntimeLogs

  alias PhoenixPaas.Deploy.Ssh

  @impl true
  def run(app, argv) when is_list(argv) do
    if local_journal?(app) do
      run_local(argv)
    else
      Ssh.run(app.server, app, argv)
    end
  end

  defp local_journal?(app) do
    System.find_executable("journalctl") != nil and local_server?(app.server)
  end

  defp local_server?(%{host_ip: host_ip}) when is_binary(host_ip) do
    host_ip in local_ipv4s()
  end

  defp local_server?(_), do: false

  defp local_ipv4s do
    case :inet.getifaddrs() do
      {:ok, ifaces} ->
        ifaces
        |> Enum.flat_map(fn {_name, opts} ->
          case Keyword.get(opts, :addr) do
            {a, b, c, d} -> ["#{a}.#{b}.#{c}.#{d}"]
            _ -> []
          end
        end)
        |> Kernel.++(["127.0.0.1"])
        |> Enum.uniq()

      _ ->
        ["127.0.0.1"]
    end
  end

  defp run_local(argv) do
    {bin, args} = local_cmd(argv)

    case System.cmd(bin, args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, _status} -> {:error, output}
    end
  end

  defp local_cmd(["sudo", "journalctl" | args]) do
    if running_as_root?() do
      {"journalctl", args}
    else
      {"sudo", ["journalctl" | args]}
    end
  end

  defp local_cmd([bin | args]), do: {bin, args}

  defp running_as_root? do
    case System.cmd("id", ["-u"], stderr_to_stdout: true) do
      {"0\n", 0} -> true
      _ -> false
    end
  end
end
