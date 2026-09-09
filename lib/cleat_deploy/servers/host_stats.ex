defmodule CleatDeploy.Servers.HostStats do
  @moduledoc """
  Cheap local CPU and network counters from /proc.

  CPU is reported on the Hetzner scale: 100% = one vCPU.
  """

  @skip_iface ~r/^(lo|docker|veth|br-|virbr|cni|flannel|tun|tap|wg)/

  def local?(%{host_ip: ip}) when is_binary(ip), do: ip in local_ipv4s()
  def local?(_), do: false

  def sample do
    with {:ok, cpu} <- cpu_counters(),
         {:ok, net} <- net_counters() do
      {:ok, %{cpu: cpu, net: net, at: System.monotonic_time(:millisecond)}}
    end
  end

  def diff(prev, now, cpu_count)
      when is_map(prev) and is_map(now) and is_integer(cpu_count) and cpu_count > 0 do
    dt_s = max(now.at - prev.at, 1) / 1000

    %{
      cpu_pct: cpu_pct(prev.cpu, now.cpu, cpu_count),
      net_in: bytes_per_sec(prev.net.in, now.net.in, dt_s),
      net_out: bytes_per_sec(prev.net.out, now.net.out, dt_s)
    }
  end

  def parse_cpu(contents) when is_binary(contents) do
    line =
      contents
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, "cpu "))

    case line && String.split(line) do
      ["cpu" | fields] when length(fields) >= 4 ->
        nums =
          fields
          |> Enum.take(8)
          |> Enum.map(&parse_int/1)

        idle = Enum.at(nums, 3, 0) + Enum.at(nums, 4, 0)
        total = Enum.sum(nums)
        {:ok, %{idle: idle, total: total}}

      _ ->
        {:error, :no_cpu}
    end
  end

  def parse_net(contents) when is_binary(contents) do
    {rx, tx} =
      contents
      |> String.split("\n")
      |> Enum.reduce({0, 0}, fn line, {in_acc, out_acc} ->
        case parse_net_line(line) do
          {rx, tx} -> {in_acc + rx, out_acc + tx}
          nil -> {in_acc, out_acc}
        end
      end)

    {:ok, %{in: rx, out: tx}}
  end

  def cpu_pct(%{idle: idle1, total: total1}, %{idle: idle2, total: total2}, cores)
      when cores > 0 do
    d_total = total2 - total1
    d_idle = idle2 - idle1

    busy =
      if d_total <= 0 do
        0.0
      else
        1.0 - d_idle / d_total
      end

    Float.round(max(busy, 0.0) * cores * 100.0, 1)
  end

  defp cpu_counters do
    case File.read("/proc/stat") do
      {:ok, contents} -> parse_cpu(contents)
      {:error, reason} -> {:error, reason}
    end
  end

  defp net_counters do
    case File.read("/proc/net/dev") do
      {:ok, contents} -> parse_net(contents)
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_net_line(line) do
    case String.split(String.trim(line), ":", parts: 2) do
      [iface, rest] ->
        iface = String.trim(iface)

        if iface != "" and not Regex.match?(@skip_iface, iface) do
          cols = String.split(rest)

          if length(cols) >= 10 do
            {parse_int(Enum.at(cols, 0)), parse_int(Enum.at(cols, 8))}
          end
        end

      _ ->
        nil
    end
  end

  defp bytes_per_sec(prev, now, dt_s) when now >= prev and dt_s > 0 do
    (now - prev) / dt_s
  end

  defp bytes_per_sec(_, _, _), do: 0.0

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp parse_int(_), do: 0

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
end
