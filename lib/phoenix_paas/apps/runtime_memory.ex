defmodule PhoenixPaas.Apps.RuntimeMemory do
  @moduledoc """
  Reads systemd cgroup memory for registered apps (server + worker units).
  """

  require Logger

  alias PhoenixPaas.Apps.App

  @unit_pattern ~r/^[A-Za-z0-9:_.@-]+$/
  @unset_memory 18_446_744_073_709_551_615
  @ssh_timeout_ms 8_000

  @callback run(App.t(), [String.t()]) :: {:ok, String.t()} | {:error, term()}

  def for_app(%App{} = app), do: Map.get(for_apps([app]), app.id)

  def for_apps(apps) when is_list(apps) do
    apps
    |> Enum.filter(& &1.server)
    |> Enum.group_by(& &1.server_id)
    |> Map.values()
    |> Task.async_stream(&fetch_server/1,
      timeout: @ssh_timeout_ms,
      on_timeout: :kill_task,
      ordered: false
    )
    |> Enum.reduce(%{}, fn
      {:ok, map}, acc when is_map(map) -> Map.merge(acc, map)
      _, acc -> acc
    end)
  end

  def format(%{bytes: bytes}) when is_integer(bytes) and bytes >= 0, do: format_bytes(bytes)
  def format(_), do: "—"

  def format_peak(%{peak_bytes: bytes}) when is_integer(bytes) and bytes >= 0,
    do: "Peak #{format_bytes(bytes)}"

  def format_peak(_), do: nil

  def format_bytes(bytes) when is_integer(bytes) and bytes < 1024, do: "#{bytes} B"

  def format_bytes(bytes) when is_integer(bytes) and bytes < 1_048_576,
    do: "#{div(bytes, 1024)} KB"

  def format_bytes(bytes) when is_integer(bytes) do
    mb = bytes / 1_048_576

    if mb < 10 do
      :erlang.float_to_binary(mb, decimals: 1) <> " MB"
    else
      "#{round(mb)} MB"
    end
  end

  defp fetch_server([]), do: %{}

  defp fetch_server([%App{} = app | _] = apps) do
    units =
      apps
      |> Enum.flat_map(&units/1)
      |> Enum.filter(&valid_unit?/1)
      |> Enum.uniq()

    if units == [] do
      %{}
    else
      case client().run(app, show_argv(units)) do
        {:ok, output} ->
          by_unit = parse_show_output(output)

          Map.new(apps, fn item ->
            {item.id, combine(units(item), by_unit)}
          end)

        {:error, reason} ->
          Logger.warning("runtime memory fetch failed for #{app.slug}: #{format_error(reason)}")
          %{}
      end
    end
  end

  defp client do
    Application.get_env(
      :phoenix_paas,
      :runtime_memory,
      PhoenixPaas.Apps.RuntimeLogsSsh
    )
  end

  defp units(%App{} = app) do
    unit = unit_name(app)

    case app.runtime do
      "golang" -> [unit, "#{unit}-worker"]
      _ -> [unit]
    end
  end

  defp unit_name(%App{} = app) do
    app.systemd_unit || App.default_systemd_unit(app.slug, app.runtime || "phoenix")
  end

  defp valid_unit?(unit) when is_binary(unit),
    do: unit != "" and Regex.match?(@unit_pattern, unit)

  defp valid_unit?(_), do: false

  defp show_argv(units) do
    ["sudo", "systemctl", "show"] ++
      units ++
      ["-p", "Id", "-p", "MemoryCurrent", "-p", "MemoryPeak", "-p", "ActiveState"]
  end

  defp parse_show_output(output) when is_binary(output) do
    output
    |> String.split(~r/\n{2,}/)
    |> Enum.map(&parse_block/1)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp parse_block(block) do
    props =
      block
      |> String.split("\n")
      |> Enum.reduce(%{}, fn line, acc ->
        case String.split(String.trim(line), "=", parts: 2) do
          [key, value] when key != "" -> Map.put(acc, key, value)
          _ -> acc
        end
      end)

    case normalize_unit(Map.get(props, "Id", "")) do
      "" ->
        nil

      unit ->
        {unit,
         %{
           bytes: parse_bytes(Map.get(props, "MemoryCurrent")),
           peak_bytes: parse_bytes(Map.get(props, "MemoryPeak")),
           active?: Map.get(props, "ActiveState") == "active"
         }}
    end
  end

  defp normalize_unit(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.replace_suffix(".service", "")
  end

  defp parse_bytes(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n >= 0 and n < @unset_memory -> n
      _ -> nil
    end
  end

  defp parse_bytes(_), do: nil

  defp combine(unit_names, by_unit) do
    parts =
      unit_names
      |> Enum.map(&Map.get(by_unit, &1))
      |> Enum.reject(&is_nil/1)

    bytes = parts |> Enum.map(& &1.bytes) |> Enum.reject(&is_nil/1)
    peaks = parts |> Enum.map(& &1.peak_bytes) |> Enum.reject(&is_nil/1)

    if bytes == [] do
      nil
    else
      %{
        bytes: Enum.sum(bytes),
        peak_bytes: if(peaks == [], do: nil, else: Enum.sum(peaks)),
        active?: Enum.any?(parts, & &1.active?)
      }
    end
  end

  defp format_error(reason) when is_binary(reason), do: String.trim(reason)
  defp format_error(reason), do: inspect(reason)
end
