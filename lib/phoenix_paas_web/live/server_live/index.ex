defmodule PhoenixPaasWeb.ServerLive.Index do
  use PhoenixPaasWeb, :live_view

  alias PhoenixPaas.Apps
  alias PhoenixPaas.Servers
  alias PhoenixPaas.Servers.{Provision, Server}

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     socket
     |> assign(:page_title, "Servers")
     |> assign(:active_tab, :servers)
     |> assign(:syncing?, false)
     |> assign(:discovered, [])
     |> assign(:confirming_server, nil)
     |> assign(:form_mode, :create)
     |> assign(:app_counts, Apps.count_apps_by_server_id(scope))
     |> stream(:servers, Servers.list_servers(scope))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New server")
    |> assign(:server, %Server{})
    |> assign(:form_mode, :create)
    |> assign(:form, to_form(Servers.change_provision(), as: :server))
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Servers")
    |> assign(:server, nil)
    |> assign(:form_mode, :create)
    |> assign(:form, nil)
  end

  @impl true
  def handle_event("set_form_mode", %{"mode" => mode}, socket) do
    mode = if mode == "register", do: :register, else: :create

    form =
      if mode == :register do
        to_form(Servers.change_server(%Server{}, %{"provider" => "hetzner", "region" => "fsn1"}))
      else
        to_form(Servers.change_provision(), as: :server)
      end

    {:noreply, socket |> assign(:form_mode, mode) |> assign(:form, form)}
  end

  def handle_event("validate", %{"server" => server_params}, socket) do
    changeset =
      case socket.assigns.form_mode do
        :create ->
          server_params
          |> Servers.change_provision()
          |> Map.put(:action, :validate)

        _ ->
          %Server{}
          |> Servers.change_server(apply_provider_defaults(server_params))
          |> Map.put(:action, :validate)
      end

    {:noreply, assign(socket, form: to_form(changeset, as: :server))}
  end

  def handle_event("save", %{"server" => server_params}, socket) do
    if socket.assigns.form_mode == :create do
      create_in_cloud(socket, server_params)
    else
      register_existing(socket, server_params)
    end
  end

  def handle_event("sync_cloud", _params, socket) do
    scope = socket.assigns.current_scope
    {result, servers} = Servers.sync_inventory(scope)

    {:noreply,
     socket
     |> assign(:syncing?, false)
     |> assign(:discovered, result.discovered)
     |> assign(:app_counts, Apps.count_apps_by_server_id(scope))
     |> assign(:server_count, length(servers))
     |> stream(:servers, servers, reset: true)
     |> put_flash(:info, inventory_flash(result))
     |> maybe_flash_errors(result.errors)}
  end

  def handle_event("confirm_remove", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    server = Servers.get_server!(scope, String.to_integer(id))
    {:noreply, assign(socket, :confirming_server, server)}
  end

  def handle_event("cancel_remove", _params, socket) do
    {:noreply, assign(socket, :confirming_server, nil)}
  end

  def handle_event("remove_server", _params, socket) do
    scope = socket.assigns.current_scope

    case socket.assigns.confirming_server do
      nil ->
        {:noreply, socket}

      server ->
        case Servers.delete_server(scope, server) do
          {:ok, deleted} ->
            servers = Servers.list_servers(scope)

            {:noreply,
             socket
             |> stream_delete(:servers, deleted)
             |> assign(:confirming_server, nil)
             |> assign(:server_count, length(servers))
             |> assign(:app_counts, Apps.count_apps_by_server_id(scope))
             |> put_flash(:info, "#{deleted.name} removed from the panel")}

          {:error, :has_apps} ->
            {:noreply,
             socket
             |> assign(:confirming_server, nil)
             |> put_flash(:error, "Move or delete this server's apps before removing it")}

          {:error, _} ->
            {:noreply,
             socket
             |> assign(:confirming_server, nil)
             |> put_flash(:error, "Could not remove server")}
        end
    end
  end

  def handle_event("register_discovered", params, socket) do
    scope = socket.assigns.current_scope
    host_ip = params["host_ip"]

    if host_ip in [nil, ""] do
      {:noreply, put_flash(socket, :error, "That cloud VM has no public IPv4 yet")}
    else
      attrs = %{
        "name" => params["name"],
        "host_ip" => host_ip,
        "provider" => params["provider"],
        "region" => params["region"] || "us-east-1",
        "aws_instance_name" => params["name"],
        "ssh_user" => "ubuntu"
      }

      case Servers.create_server(scope, attrs) do
        {:ok, server} ->
          discovered =
            Enum.reject(socket.assigns.discovered, fn remote ->
              remote.name == server.name and remote.provider == server.provider
            end)

          {:noreply,
           socket
           |> stream_insert(:servers, server)
           |> assign(:discovered, discovered)
           |> assign(:server_count, socket.assigns.server_count + 1)
           |> put_flash(:info, "#{server.name} registered")}

        {:error, %Ecto.Changeset{}} ->
          {:noreply, put_flash(socket, :error, "Could not register #{params["name"]}")}
      end
    end
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
      <div class="space-y-4">
        <div class="flex items-center justify-between gap-4">
          <div>
            <h2 class="font-display text-sm font-semibold text-hd-text">Deploy servers</h2>
            <p class="text-[11px] text-hd-muted">
              Hetzner Cloud and AWS Lightsail VMs hosting Phoenix and Go applications
            </p>
          </div>
          <div :if={@live_action == :index} class="flex items-center gap-2">
            <button
              id="sync-cloud-button"
              type="button"
              phx-click="sync_cloud"
              phx-disable-with="Checking…"
              class="paas-btn-secondary"
            >
              <.icon name="hero-arrow-path" class="size-3.5" /> Check cloud
            </button>
            <.link navigate={~p"/servers/new"} class="paas-btn-primary">
              <.icon name="hero-plus" class="size-3.5" /> New server
            </.link>
          </div>
        </div>

        <div :if={@live_action == :new} class="paas-card overflow-hidden">
          <div class="flex flex-wrap items-center justify-between gap-3 border-b border-hd-border px-4 py-3">
            <div>
              <h3 class="font-display text-sm font-semibold text-hd-text">New Hetzner VM</h3>
              <p class="text-[11px] text-hd-muted">
                Creates a real Ubuntu box in Hetzner Cloud and registers it here
              </p>
            </div>
            <div class="flex rounded-md border border-hd-border bg-hd-aside p-0.5 text-[11px] font-semibold">
              <button
                id="form-mode-create"
                type="button"
                phx-click="set_form_mode"
                phx-value-mode="create"
                class={[
                  "rounded px-2.5 py-1 transition-colors",
                  @form_mode != :register && "bg-hd-card text-hd-text",
                  @form_mode == :register && "text-hd-muted hover:text-hd-text"
                ]}
              >
                Create in cloud
              </button>
              <button
                id="form-mode-register"
                type="button"
                phx-click="set_form_mode"
                phx-value-mode="register"
                class={[
                  "rounded px-2.5 py-1 transition-colors",
                  @form_mode == :register && "bg-hd-card text-hd-text",
                  @form_mode != :register && "text-hd-muted hover:text-hd-text"
                ]}
              >
                Register existing
              </button>
            </div>
          </div>

          <div :if={@form_mode != :register} class="space-y-5 p-4">
            <.form
              for={@form}
              id="create-server-form"
              phx-change="validate"
              phx-submit="save"
              class="space-y-5"
            >
              <input type="hidden" name={@form[:provider].name} value="hetzner" />
              <div class="grid gap-4 sm:grid-cols-2">
                <.input
                  field={@form[:name]}
                  type="text"
                  label="Server name"
                  placeholder="gestaobem-cx33"
                  required
                />
                <.input
                  field={@form[:region]}
                  type="select"
                  label="Location"
                  options={Provision.locations()}
                />
              </div>

              <div class="space-y-2">
                <p class="font-mono text-[10px] font-semibold uppercase tracking-wider text-hd-muted">
                  Plan
                </p>
                <div id="bundle-picker" class="grid gap-2 sm:grid-cols-2 lg:grid-cols-4">
                  <label
                    :for={bundle <- Provision.bundles()}
                    id={"bundle-#{bundle.bundle_id}"}
                    class={[
                      "relative cursor-pointer rounded-lg border p-3 transition-all",
                      @form[:bundle_id].value == bundle.bundle_id &&
                        "border-hd-orange bg-hd-orange/10",
                      @form[:bundle_id].value != bundle.bundle_id &&
                        "border-hd-border bg-hd-aside hover:border-hd-muted"
                    ]}
                  >
                    <input
                      type="radio"
                      name={@form[:bundle_id].name}
                      value={bundle.bundle_id}
                      checked={@form[:bundle_id].value == bundle.bundle_id}
                      class="sr-only"
                    />
                    <div class="flex items-start justify-between gap-2">
                      <p class="font-display text-sm font-semibold text-hd-text">
                        {bundle.bundle_name}
                      </p>
                      <span
                        :if={bundle.bundle_id == "cx33"}
                        class="rounded-full border border-hd-orange/40 px-1.5 py-0.5 font-mono text-[9px] uppercase tracking-wide text-hd-orange"
                      >
                        Rec
                      </span>
                    </div>
                    <p class="mt-1 font-mono text-[11px] text-hd-muted">
                      {bundle.cpu_count} vCPU · {PhoenixPaas.Servers.Server.format_ram(
                        %PhoenixPaas.Servers.Server{ram_mb: bundle.ram_mb}
                      )} · {bundle.disk_gb} GB
                    </p>
                    <p class="mt-2 font-mono text-xs font-semibold text-hd-text">
                      €{Decimal.round(bundle.monthly_price_usd, 2)}/mo
                    </p>
                  </label>
                </div>
              </div>

              <.input
                field={@form[:deploy_mode]}
                type="select"
                label="Deploy mode"
                options={[
                  {"Shared (multiple apps)", "shared"},
                  {"Dedicated (solo app)", "dedicated"}
                ]}
              />

              <p class="text-[11px] leading-relaxed text-hd-muted">
                Ubuntu 24.04, user <span class="font-mono text-hd-text">ubuntu</span>, SSH key
                reused from an existing server or generated automatically. Public IPv4 comes
                from Hetzner after the VM boots.
              </p>

              <div class="flex gap-2">
                <button
                  type="submit"
                  class="paas-btn-primary"
                  phx-disable-with="Creating in Hetzner…"
                >
                  <.icon name="hero-cloud" class="size-3.5" /> Create VM
                </button>
                <.link navigate={~p"/servers"} class="paas-btn-secondary">Cancel</.link>
              </div>
            </.form>
          </div>

          <div :if={@form_mode == :register} class="space-y-4 p-4">
            <p class="text-[11px] text-hd-muted">
              Use this only for a box that already exists (Tailscale or an imported IP).
            </p>
            <.form
              for={@form}
              id="server-form"
              phx-change="validate"
              phx-submit="save"
              class="space-y-4"
            >
              <div class="grid gap-4 sm:grid-cols-2">
                <.input field={@form[:name]} type="text" label="Name" required />
                <.input field={@form[:host_ip]} type="text" label="Host IP" required />
                <.input
                  field={@form[:provider]}
                  type="select"
                  label="Provider"
                  options={[
                    {"Hetzner Cloud", "hetzner"},
                    {"AWS Lightsail", "lightsail"}
                  ]}
                />
                <.input field={@form[:ssh_user]} type="text" label="SSH user" />
                <.input field={@form[:region]} type="text" label="Region / location" />
                <.input
                  field={@form[:aws_instance_name]}
                  type="text"
                  label="Instance name"
                />
                <.input
                  field={@form[:deploy_mode]}
                  type="select"
                  label="Deploy mode"
                  options={[
                    {"Shared (multiple apps)", "shared"},
                    {"Dedicated (solo app)", "dedicated"}
                  ]}
                />
                <.input
                  field={@form[:ssh_private_key]}
                  type="textarea"
                  label="SSH private key (PEM)"
                  class="col-span-full font-mono text-xs"
                  placeholder="-----BEGIN OPENSSH PRIVATE KEY-----"
                />
              </div>
              <div class="flex gap-2">
                <button type="submit" class="paas-btn-primary">Save server</button>
                <.link navigate={~p"/servers"} class="paas-btn-secondary">Cancel</.link>
              </div>
            </.form>
          </div>
        </div>

        <div class="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          <div id="servers-list" phx-update="stream" class="contents">
            <div
              id="servers-empty"
              class="hidden only:block rounded-md border-2 border-dashed border-hd-border p-8 text-center md:col-span-2 lg:col-span-3"
            >
              <div class="mx-auto mb-4 flex size-12 animate-pulse items-center justify-center rounded-md border border-hd-border bg-hd-aside text-hd-orange">
                <.icon name="hero-server-stack" class="size-6" />
              </div>
              <h3 class="font-display text-sm font-semibold text-hd-text">
                No registered VM instances
              </h3>
              <p class="mx-auto mt-1 max-w-md text-xs leading-relaxed text-hd-muted">
                Register a Hetzner Cloud or AWS Lightsail VM with its SSH key to start deploying.
              </p>
              <.link navigate={~p"/servers/new"} class="paas-btn-primary mt-4 inline-flex">
                Register New Server
              </.link>
            </div>

            <div
              :for={{id, server} <- @streams.servers}
              id={id}
              class={[
                "paas-card flex flex-col justify-between p-4 transition-all hover:border-hd-orange/30",
                server.instance_status == "missing" && "border-rose-500/40"
              ]}
            >
              <.link navigate={~p"/servers/#{server.id}"} class="space-y-3">
                <div class="flex items-start justify-between">
                  <div class="space-y-0.5">
                    <h3 class="font-display text-xs font-semibold text-hd-text">{server.name}</h3>
                    <div class="flex flex-wrap gap-1">
                      <span class="inline-block rounded border border-hd-border bg-hd-bg px-2 py-0.5 font-mono text-[9px] font-medium text-hd-orange">
                        {server.provider || "lightsail"}
                      </span>
                      <span class="inline-block rounded border border-hd-border bg-hd-bg px-2 py-0.5 font-mono text-[9px] font-medium text-hd-muted">
                        {server.region}
                      </span>
                      <span class={[
                        "inline-block rounded border px-2 py-0.5 font-mono text-[9px] font-medium",
                        server.deploy_mode == "dedicated" &&
                          "border-hd-orange/40 bg-hd-orange/10 text-hd-orange",
                        server.deploy_mode != "dedicated" && "border-hd-border bg-hd-bg text-hd-muted"
                      ]}>
                        {if server.deploy_mode == "dedicated", do: "Dedicated", else: "Shared"}
                      </span>
                    </div>
                  </div>
                  <span class="flex items-center gap-1.5 rounded border border-hd-border bg-hd-bg px-2 py-0.5 font-mono text-[10px]">
                    <span class={["size-1.5 rounded-full", status_dot_class(server.instance_status)]} />
                    <span class={["font-semibold", status_text_class(server.instance_status)]}>
                      {status_label(server.instance_status)}
                    </span>
                  </span>
                </div>

                <div
                  :if={PhoenixPaas.Servers.Server.specs_configured?(server)}
                  class="grid grid-cols-3 gap-2 font-mono text-[10px]"
                >
                  <div class="rounded border border-hd-border bg-hd-bg px-2 py-1 text-center">
                    <p class="text-hd-muted">Plan</p>
                    <p class="font-semibold text-hd-text">{server.bundle_name}</p>
                  </div>
                  <div class="rounded border border-hd-border bg-hd-bg px-2 py-1 text-center">
                    <p class="text-hd-muted">RAM</p>
                    <p class="font-semibold text-hd-text">
                      {PhoenixPaas.Servers.Server.format_ram(server)}
                    </p>
                  </div>
                  <div class="rounded border border-hd-border bg-hd-bg px-2 py-1 text-center">
                    <p class="text-hd-muted">vCPU</p>
                    <p class="font-semibold text-hd-text">{server.cpu_count}</p>
                  </div>
                </div>

                <div
                  :if={not PhoenixPaas.Servers.Server.specs_configured?(server)}
                  class="rounded border border-dashed border-hd-border px-2.5 py-2 text-center text-[10px] text-hd-muted"
                >
                  {status_hint(server.instance_status)}
                </div>

                <div class="flex items-center justify-between rounded border border-hd-border bg-hd-bg px-2.5 py-1.5 font-mono text-[11px]">
                  <span class="text-hd-muted">Static IP:</span>
                  <span class="font-bold tracking-wider text-hd-text">{server.host_ip}</span>
                  <button
                    id={"copy-ip-#{server.id}"}
                    type="button"
                    phx-hook=".Copy"
                    data-clipboard={server.host_ip}
                    class="text-hd-muted transition-colors hover:text-hd-text"
                    aria-label="Copy IP"
                  >
                    <.icon name="hero-clipboard-document" class="size-3.5" />
                  </button>
                </div>
              </.link>

              <button
                :if={removable_from_panel?(server, @app_counts)}
                id={"remove-server-#{server.id}"}
                type="button"
                phx-click="confirm_remove"
                phx-value-id={server.id}
                class="mt-3 w-full rounded border border-rose-500/40 px-2 py-1.5 font-mono text-[10px] font-semibold text-rose-400 transition-colors hover:bg-rose-500/10"
              >
                Remove from panel
              </button>
            </div>
          </div>

          <.link
            id="add-server-card"
            navigate={~p"/servers/new"}
            class="flex cursor-pointer flex-col items-center justify-center rounded-md border-2 border-dashed border-hd-border p-4 text-center transition-all hover:border-hd-muted hover:bg-hd-card/10"
          >
            <div class="flex size-8 items-center justify-center rounded-full border border-hd-border text-hd-muted">
              <.icon name="hero-plus" class="size-4" />
            </div>
            <p class="mt-1.5 text-[11px] font-semibold text-hd-text">Add server</p>
            <p class="text-[10px] text-hd-muted">Hetzner or Lightsail</p>
          </.link>
        </div>

        <div :if={@discovered != []} id="discovered-servers" class="space-y-3">
          <div>
            <h3 class="font-display text-sm font-semibold text-hd-text">Found in the cloud</h3>
            <p class="text-[11px] text-hd-muted">
              VMs in Hetzner or Lightsail that are not registered in this panel yet
            </p>
          </div>
          <div class="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            <div
              :for={remote <- @discovered}
              id={"discovered-#{remote.provider}-#{remote.name}"}
              class="paas-card space-y-3 p-4"
            >
              <div class="flex items-start justify-between gap-2">
                <div>
                  <h4 class="font-display text-xs font-semibold text-hd-text">{remote.name}</h4>
                  <p class="font-mono text-[11px] text-hd-muted">
                    {remote.provider} · {remote.region || "—"}
                  </p>
                </div>
                <span class="font-mono text-[10px] font-semibold text-hd-green">NEW</span>
              </div>
              <p class="font-mono text-[11px] text-hd-text">{remote.public_ip || "no public IPv4"}</p>
              <button
                id={"register-#{remote.provider}-#{remote.name}"}
                type="button"
                phx-click="register_discovered"
                phx-value-name={remote.name}
                phx-value-host_ip={remote.public_ip}
                phx-value-provider={remote.provider}
                phx-value-region={remote.region}
                class="paas-btn-secondary w-full"
              >
                Register
              </button>
            </div>
          </div>
        </div>

        <div
          :if={@confirming_server}
          id="remove-confirm-modal"
          class="fixed inset-0 z-50 flex items-center justify-center p-4"
          phx-window-keydown="cancel_remove"
          phx-key="Escape"
          role="presentation"
        >
          <button
            type="button"
            class="paas-modal-backdrop absolute inset-0 bg-black/70 backdrop-blur-sm"
            phx-click="cancel_remove"
            aria-label="Close confirmation"
          />
          <div
            role="dialog"
            aria-modal="true"
            aria-labelledby="remove-confirm-title"
            class="paas-modal-panel relative w-full max-w-md overflow-hidden rounded-xl border border-hd-border bg-hd-card shadow-[0_24px_80px_rgba(0,0,0,0.55)]"
          >
            <div class="h-px bg-gradient-to-r from-transparent via-rose-500/70 to-transparent" />
            <div class="space-y-5 p-5 sm:p-6">
              <div class="flex items-start gap-3">
                <div class="flex size-11 shrink-0 items-center justify-center rounded-full border border-rose-500/30 bg-rose-500/10 text-rose-400">
                  <.icon name="hero-exclamation-triangle" class="size-5" />
                </div>
                <div class="min-w-0 space-y-1">
                  <h3
                    id="remove-confirm-title"
                    class="font-display text-base font-semibold text-hd-text"
                  >
                    Remove this server?
                  </h3>
                  <p class="text-[13px] leading-relaxed text-hd-muted">
                    It is not in Hetzner or Lightsail. This only drops it from the panel — the
                    machine is not deleted.
                  </p>
                </div>
              </div>

              <div class="rounded-lg border border-hd-border bg-hd-aside px-3 py-3">
                <p class="font-display text-sm font-semibold text-hd-text">
                  {@confirming_server.name}
                </p>
                <p class="mt-1 font-mono text-[11px] text-hd-muted">
                  {@confirming_server.provider} · {@confirming_server.region} · {@confirming_server.host_ip}
                </p>
              </div>

              <div class="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
                <button
                  id="cancel-remove-server"
                  type="button"
                  phx-click="cancel_remove"
                  class="paas-btn-secondary justify-center"
                >
                  Keep it
                </button>
                <button
                  id="confirm-remove-server"
                  type="button"
                  phx-click="remove_server"
                  phx-disable-with="Removing…"
                  class="inline-flex items-center justify-center gap-1.5 rounded-md bg-rose-500 px-3 py-1.5 text-xs font-bold text-white transition-colors hover:bg-rose-400"
                >
                  <.icon name="hero-trash" class="size-3.5" /> Yes, remove it
                </button>
              </div>
            </div>
          </div>
        </div>

        <script :type={Phoenix.LiveView.ColocatedHook} name=".Copy">
          export default {
            mounted() {
              this.el.addEventListener("click", (event) => {
                event.preventDefault();
                event.stopPropagation();
                navigator.clipboard.writeText(this.el.dataset.clipboard || "");
              });
            }
          }
        </script>
      </div>
    </Layouts.app>
    """
  end

  defp create_in_cloud(socket, server_params) do
    case Servers.provision_server(socket.assigns.current_scope, server_params) do
      {:ok, server} ->
        {:noreply,
         socket
         |> stream_insert(:servers, server)
         |> assign(:server_count, socket.assigns.server_count + 1)
         |> put_flash(:info, "#{server.name} is running at #{server.host_ip}")
         |> push_navigate(to: ~p"/servers")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :server))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Servers.format_cloud_error(reason))}
    end
  end

  defp register_existing(socket, server_params) do
    server_params = apply_provider_defaults(server_params)

    case Servers.create_server(socket.assigns.current_scope, server_params) do
      {:ok, server} ->
        {:noreply,
         socket
         |> stream_insert(:servers, server)
         |> assign(:server_count, socket.assigns.server_count + 1)
         |> put_flash(:info, "Server registered")
         |> push_navigate(to: ~p"/servers")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :server))}
    end
  end

  defp apply_provider_defaults(%{"provider" => "hetzner"} = params) do
    params
    |> put_if_blank_or("region", "fsn1", ["", "us-east-1"])
    |> put_if_blank_or("ssh_user", "ubuntu", ["", nil])
  end

  defp apply_provider_defaults(params), do: params

  defp put_if_blank_or(params, key, value, replace) do
    current = Map.get(params, key)

    if current in replace do
      Map.put(params, key, value)
    else
      params
    end
  end

  defp inventory_flash(result) do
    running = Enum.count(result.updated, &(&1.instance_status == "running"))
    missing = length(result.missing)
    discovered = length(result.discovered)
    private = length(result.private)

    "Cloud check: #{running} running, #{missing} missing, #{private} private, #{discovered} new"
  end

  defp maybe_flash_errors(socket, []), do: socket

  defp maybe_flash_errors(socket, errors) do
    names = errors |> Enum.map(&elem(&1, 0)) |> Enum.join(", ")
    put_flash(socket, :error, "Could not check: #{names}")
  end

  defp status_label(nil), do: "UNKNOWN"
  defp status_label(status), do: String.upcase(status)

  defp status_dot_class("running"), do: "animate-pulse bg-hd-green"
  defp status_dot_class("missing"), do: "bg-rose-500"
  defp status_dot_class("private"), do: "bg-sky-400"
  defp status_dot_class(_), do: "bg-hd-muted"

  defp status_text_class("missing"), do: "text-rose-400"
  defp status_text_class("running"), do: "text-hd-green"
  defp status_text_class("private"), do: "text-sky-400"
  defp status_text_class(_), do: "text-hd-muted"

  defp status_hint("missing"), do: "Gone from Hetzner / Lightsail"
  defp status_hint("private"), do: "Private network — not in the cloud APIs"
  defp status_hint(_), do: "Open to sync cloud specs"

  defp removable_from_panel?(server, app_counts) do
    server.instance_status in ["missing", "private"] and Map.get(app_counts, server.id, 0) == 0
  end
end
