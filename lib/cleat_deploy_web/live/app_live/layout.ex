defmodule CleatDeployWeb.AppLive.Layout do
  @moduledoc false
  use CleatDeployWeb, :html

  import CleatDeployWeb.CoreComponents, only: [icon: 1]

  attr :app, :map, required: true
  attr :apps, :list, required: true

  def shell_header(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center justify-between gap-3 border-b border-hd-border/40 pb-3">
      <div class="flex items-center gap-2">
        <span class="font-mono text-[10px] uppercase tracking-wider text-hd-muted">
          Active Application:
        </span>
        <select
          id="app-selector"
          class="paas-select"
          phx-change="select_app"
          name="app_id"
        >
          <option :for={app <- @apps} value={app.id} selected={app.id == @app.id}>
            {app.name} ({app.branch})
          </option>
        </select>
      </div>
      <div class="text-xs text-hd-muted">
        Repository mapping: <span class="font-mono text-hd-orange">{@app.github_repo}</span>
      </div>
    </div>
    """
  end

  attr :app, :map, required: true
  attr :deploying?, :boolean, required: true

  def shell_hero(assigns) do
    ~H"""
    <div class="paas-card flex flex-col gap-3 p-4 md:flex-row md:items-center md:justify-between">
      <div class="flex items-center gap-2">
        <span class="inline-flex h-7 w-12 items-center justify-center rounded border border-hd-border bg-hd-aside font-mono text-[10px] font-bold text-hd-orange">
          PHX
        </span>
        <div>
          <h2 class="font-display text-base font-semibold text-hd-text">{@app.name}</h2>
          <p class="flex items-center gap-1 font-mono text-[11px] text-hd-muted">
            <.icon name="hero-code-bracket" class="size-3" />
            {@app.github_repo}
            <span class="text-hd-border">|</span> branch: {@app.branch}
          </p>
        </div>
      </div>

      <button
        id="deploy-button"
        type="button"
        phx-click="deploy"
        disabled={@deploying?}
        class={["paas-btn-primary uppercase", @deploying? && "opacity-50"]}
      >
        <.icon
          name={if @deploying?, do: "hero-arrow-path", else: "hero-play"}
          class={["size-3.5", @deploying? && "motion-safe:animate-spin"]}
        />
        {if @deploying?, do: "Build in progress…", else: "Deploy now"}
      </button>
    </div>
    """
  end

  attr :app, :map, required: true
  attr :memory, :any, default: nil

  def shell_info_tiles(assigns) do
    peak = CleatDeploy.Apps.RuntimeMemory.format_peak(assigns.memory)

    assigns =
      assign(assigns,
        ram_label: CleatDeploy.Apps.RuntimeMemory.format(assigns.memory),
        ram_sub: peak || "systemd cgroup",
        cpu_label: CleatDeploy.Apps.RuntimeMemory.format_cpu(assigns.memory),
        disk_label: CleatDeploy.Apps.RuntimeMemory.format_disk(assigns.memory)
      )

    ~H"""
    <div class="space-y-3">
      <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <.info_tile label="Domain Host" value={@app.host} mono sub="IPv4 ingress endpoint" />
        <.info_tile label="Deploy Branch" value={@app.branch} mono sub="Git HEAD target" />
        <.info_tile label="Target Server" value={@app.server.host_ip} mono sub={@app.server.name} />
        <.info_tile
          label="Auto Deploy"
          value={if @app.auto_deploy, do: "Webhook Enabled", else: "Manual Selector"}
          sub="HMAC Sha256 keys"
        />
      </div>
      <div class="grid gap-3 sm:grid-cols-3">
        <.info_tile id="app-memory-tile" label="Memory" value={@ram_label} mono sub={@ram_sub} />
        <.info_tile id="app-cpu-tile" label="CPU" value={@cpu_label} mono sub="Share of one vCPU" />
        <.info_tile id="app-disk-tile" label="Disk" value={@disk_label} mono sub="Release + data" />
      </div>
    </div>
    """
  end

  attr :app, :map, required: true
  attr :active_tab, :atom, required: true
  attr :detail_tabs, :list, required: true

  def tab_bar(assigns) do
    ~H"""
    <div
      role="tablist"
      aria-label="App configuration"
      class="flex flex-wrap items-center gap-1 border-b border-hd-border bg-hd-aside p-1"
    >
      <.detail_tab_link
        tab={:deployments}
        label="Deployments"
        icon="hero-rocket-launch"
        active?={@active_tab == :deployments}
        href={~p"/apps/#{@app.id}/deployments"}
      />
      <.detail_tab_link
        tab={:logs}
        label="Logs"
        icon="hero-command-line"
        active?={@active_tab == :logs}
        href={~p"/apps/#{@app.id}?tab=logs"}
      />
      <.detail_tab_link
        :if={:domains in @detail_tabs}
        tab={:domains}
        label="Tenant domains"
        icon="hero-globe-alt"
        active?={@active_tab == :domains}
        href={~p"/apps/#{@app.id}?tab=domains"}
      />
      <.detail_tab_link
        tab={:environment}
        label="Environment"
        icon="hero-circle-stack"
        active?={@active_tab == :environment}
        href={~p"/apps/#{@app.id}?tab=environment"}
      />
      <.detail_tab_link
        :if={:runtime in @detail_tabs}
        tab={:runtime}
        label="Runtime"
        icon="hero-cube"
        active?={@active_tab == :runtime}
        href={~p"/apps/#{@app.id}?tab=runtime"}
      />
      <.detail_tab_link
        tab={:webhook}
        label="Webhook"
        icon="hero-link"
        active?={@active_tab == :webhook}
        href={~p"/apps/#{@app.id}?tab=webhook"}
      />
    </div>
    """
  end

  attr :tab, :atom, required: true
  attr :label, :string, required: true
  attr :icon, :string, required: true
  attr :active?, :boolean, required: true
  attr :href, :string, required: true

  defp detail_tab_link(assigns) do
    ~H"""
    <.link
      id={"app-detail-tab-#{@tab}"}
      navigate={@href}
      role="tab"
      aria-selected={@active?}
      class={[
        "flex items-center gap-1.5 rounded-md px-3 py-1.5 text-xs font-semibold tracking-wide transition-all",
        @active? && "border border-hd-border bg-hd-card text-hd-orange",
        !@active? && "text-hd-muted hover:text-hd-text"
      ]}
    >
      <.icon name={@icon} class="size-3.5" />
      <span>{@label}</span>
    </.link>
    """
  end

  def detail_tabs(custom_domain_app?, runtime_packages) do
    [:deployments, :logs]
    |> then(fn tabs -> if custom_domain_app?, do: tabs ++ [:domains], else: tabs end)
    |> Kernel.++([:environment])
    |> then(fn tabs -> if runtime_packages != [], do: tabs ++ [:runtime], else: tabs end)
    |> Kernel.++([:webhook])
  end

  def parse_detail_tab(tab)
      when tab in ["logs", "domains", "environment", "runtime", "webhook"] do
    String.to_existing_atom(tab)
  end

  def parse_detail_tab(_), do: :environment
end
