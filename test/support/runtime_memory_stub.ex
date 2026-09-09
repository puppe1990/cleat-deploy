defmodule CleatDeploy.Apps.RuntimeMemoryStub do
  @moduledoc false
  @behaviour CleatDeploy.Apps.RuntimeMemory

  @impl true
  def run(_app, argv) when is_list(argv) do
    units = extract_units(argv)
    paths = extract_paths(argv)

    show = Enum.map_join(units, "\n\n", &unit_block/1)
    ps = Enum.map_join(units, "\n", &ps_line/1)
    du = Enum.map_join(paths, "\n", &du_line/1)

    {:ok, show <> "\n__PAAS_PS__\n" <> ps <> "\n__PAAS_DU__\n" <> du}
  end

  defp extract_units(["bash", "-c", script]) when is_binary(script) do
    case Regex.run(~r/systemctl show (.+) -p Id/, script) do
      [_, part] -> quoted_tokens(part)
      _ -> []
    end
  end

  defp extract_units(argv) when is_list(argv) do
    argv
    |> Enum.drop_while(&(&1 != "show"))
    |> Enum.drop(1)
    |> Enum.take_while(&(not String.starts_with?(&1, "-")))
  end

  defp extract_paths(["bash", "-c", script]) when is_binary(script) do
    case Regex.run(~r/du -sb (.+) 2>/, script) do
      [_, part] -> quoted_tokens(part)
      _ -> []
    end
  end

  defp extract_paths(_), do: []

  defp quoted_tokens(part) do
    Regex.scan(~r/'([^']+)'/, part)
    |> Enum.map(fn [_, token] -> token end)
  end

  defp unit_block(unit) do
    bytes = if String.ends_with?(unit, "-worker"), do: 10_416_128, else: 171_200_512
    peak = bytes + 16_777_216

    """
    Id=#{unit}.service
    MemoryCurrent=#{bytes}
    MemoryPeak=#{peak}
    ActiveState=active
    """
  end

  defp ps_line(unit) do
    cpu = if String.ends_with?(unit, "-worker"), do: "1.7", else: "2.8"
    " #{cpu} #{unit}.service"
  end

  defp du_line(path) do
    bytes = if String.contains?(path, "/var/lib/"), do: 10_485_760, else: 524_288_000
    "#{bytes}\t#{path}"
  end
end
