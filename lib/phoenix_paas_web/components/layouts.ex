defmodule PhoenixPaasWeb.Layouts do
  @moduledoc """
  Layouts for Phoenix PaaS control panel.
  """
  use PhoenixPaasWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :active_tab, :atom, default: :dashboard
  attr :server_count, :integer, default: 0
  attr :app_count, :integer, default: 0
  attr :current_scope, :map, default: nil

  slot :inner_block, required: true

  def app(assigns) do
    if assigns.active_tab == :auth do
      ~H"""
      <div class="relative flex min-h-screen flex-col items-center justify-center bg-hd-bg px-4 py-12 text-hd-text antialiased">
        <div class="absolute top-4 right-4">
          <PaasShell.theme_toggle id="theme-toggle-auth" />
        </div>
        <div class="mb-8 flex items-center gap-2.5">
          <div class="flex size-9 items-center justify-center rounded-lg border border-hd-border bg-hd-card">
            <.icon name="hero-fire" class="size-5 text-hd-orange" />
          </div>
          <h1 class="font-display text-lg font-semibold tracking-tight">Phoenix PaaS</h1>
        </div>

        <div class="w-full max-w-sm space-y-4">
          <.flash kind={:info} flash={@flash} />
          <.flash kind={:error} flash={@flash} />
          {render_slot(@inner_block)}
        </div>
      </div>
      """
    else
      ~H"""
      <PaasShell.shell
        flash={@flash}
        active_tab={@active_tab}
        server_count={@server_count}
        app_count={@app_count}
        current_scope={@current_scope}
      >
        {render_slot(@inner_block)}
      </PaasShell.shell>
      """
    end
  end
end
