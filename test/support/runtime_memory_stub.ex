defmodule PhoenixPaas.Apps.RuntimeMemoryStub do
  @moduledoc false
  @behaviour PhoenixPaas.Apps.RuntimeMemory

  @impl true
  def run(_app, argv) when is_list(argv) do
    output =
      argv
      |> show_units()
      |> Enum.map_join("\n\n", &unit_block/1)

    {:ok, output}
  end

  defp show_units(argv) do
    argv
    |> Enum.drop_while(&(&1 != "show"))
    |> Enum.drop(1)
    |> Enum.take_while(&(not String.starts_with?(&1, "-")))
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
end
