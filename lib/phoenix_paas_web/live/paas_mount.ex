defmodule PhoenixPaasWeb.PaasMount do
  @moduledoc false
  import Phoenix.Component

  alias PhoenixPaas.{Apps, Servers}

  def on_mount(:default, _params, _session, socket) do
    scope = socket.assigns.current_scope

    {:cont,
     socket
     |> assign(:server_count, Servers.count_servers(scope))
     |> assign(:app_count, Apps.count_apps(scope))}
  end
end
