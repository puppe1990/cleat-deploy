defmodule PhoenixPaasWeb.DashboardLive do
  use PhoenixPaasWeb, :live_view

  alias PhoenixPaas.Servers.Insights

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     assign(socket,
       page_title: "Dashboard",
       active_tab: :dashboard,
       insights: Insights.snapshot(scope, metrics: connected?(socket))
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active_tab={@active_tab}
      server_count={@server_count}
      app_count={@app_count}
    >
      <div id="dashboard" class="space-y-4">
        <div
          :if={@insights.server}
          id="server-overview"
          class="paas-card flex flex-wrap items-center justify-between gap-3 px-4 py-3"
        >
          <div class="min-w-0">
            <p class="font-mono text-[10px] font-semibold uppercase tracking-wider text-hd-muted">
              Active server
            </p>
            <h2 class="font-display text-lg font-semibold tracking-tight text-hd-text">
              {@insights.server.name}
            </h2>
            <p class="font-mono text-[11px] text-hd-muted">
              {server_spec(@insights.server)}
            </p>
          </div>
          <span class={[
            "rounded border px-2 py-0.5 font-mono text-[10px] font-semibold uppercase tracking-wide",
            status_class(@insights.server.instance_status)
          ]}>
            {@insights.server.instance_status || "unknown"}
          </span>
        </div>

        <div class="grid gap-4 md:grid-cols-2">
          <.link navigate={~p"/servers"} class="block">
            <.metric_card
              title="Registered servers"
              value={Integer.to_string(@server_count)}
              hint="Active Hypervisors"
              icon="hero-server-stack"
            />
          </.link>

          <.link navigate={~p"/apps"} class="block">
            <.metric_card
              title="Configured apps"
              value={Integer.to_string(@app_count)}
              hint="Live Routes"
              icon="hero-globe-alt"
            />
          </.link>
        </div>

        <div id="server-charts" class="grid gap-4 lg:grid-cols-2">
          <.area_chart
            id="chart-cpu"
            title="CPU · 24h"
            hint="Hetzner utilization"
            current={format_cpu(@insights.cpu_now)}
            series={@insights.metrics.cpu}
          />
          <.dual_line_chart
            id="chart-network"
            title="Network · 24h"
            hint="Bandwidth in / out"
            current={format_net(@insights.net_in_now, @insights.net_out_now)}
            inbound={@insights.metrics.network_in}
            outbound={@insights.metrics.network_out}
          />
          <.runtime_bars
            id="chart-runtimes"
            elixir={@insights.runtimes.elixir}
            go={@insights.runtimes.go}
          />
          <.deploy_bars id="chart-deploys" days={@insights.deploys} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp server_spec(server) do
    parts =
      [
        server.bundle_name,
        cpu_label(server.cpu_count),
        ram_label(server.ram_mb),
        disk_label(server.disk_gb),
        server.region
      ]
      |> Enum.reject(&is_nil/1)

    if parts == [], do: server.host_ip || "—", else: Enum.join(parts, " · ")
  end

  defp cpu_label(n) when is_integer(n) and n > 0, do: "#{n} vCPU"
  defp cpu_label(_), do: nil

  defp ram_label(mb) when is_integer(mb) and mb >= 1024, do: "#{div(mb, 1024)} GB RAM"
  defp ram_label(mb) when is_integer(mb) and mb > 0, do: "#{mb} MB RAM"
  defp ram_label(_), do: nil

  defp disk_label(gb) when is_integer(gb) and gb > 0, do: "#{gb} GB disk"
  defp disk_label(_), do: nil

  defp status_class("running"), do: "border-hd-green/40 bg-hd-green/10 text-hd-green"
  defp status_class("missing"), do: "border-rose-500/40 bg-rose-500/10 text-rose-400"
  defp status_class(_), do: "border-hd-border bg-hd-aside text-hd-muted"

  defp format_cpu(nil), do: "—"

  defp format_cpu(value) when is_number(value) do
    :erlang.float_to_binary(value / 1, decimals: 1) <> "%"
  end

  defp format_net(nil, nil), do: "—"

  defp format_net(inbound, outbound) do
    "#{format_bps(inbound)} in · #{format_bps(outbound)} out"
  end

  defp format_bps(nil), do: "—"
  defp format_bps(v) when v >= 1_000_000, do: rate(v / 1_000_000, "MB/s")
  defp format_bps(v) when v >= 1_000, do: rate(v / 1_000, "KB/s")
  defp format_bps(v), do: rate(v, "B/s")

  defp rate(v, unit), do: :erlang.float_to_binary(v / 1, decimals: 1) <> " " <> unit
end
