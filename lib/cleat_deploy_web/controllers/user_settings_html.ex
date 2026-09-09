defmodule CleatDeployWeb.UserSettingsHTML do
  use CleatDeployWeb, :html

  embed_templates "user_settings_html/*"

  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  slot :inner_block, required: true

  def settings_section(assigns) do
    ~H"""
    <section class="paas-card overflow-hidden">
      <div class="flex items-start gap-3 border-b border-hd-border bg-hd-aside/60 px-4 py-3.5">
        <div class="flex size-9 shrink-0 items-center justify-center rounded-md border border-hd-border bg-hd-card">
          <.icon name={@icon} class="size-4 text-hd-orange" />
        </div>
        <div class="min-w-0 space-y-0.5">
          <h3 class="font-display text-sm font-semibold text-hd-text">{@title}</h3>
          <p class="text-xs leading-relaxed text-hd-muted">{@description}</p>
        </div>
      </div>
      <div class="p-4">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  attr :label, :string, required: true

  def password_requirement(assigns) do
    ~H"""
    <li class="flex items-center gap-2 text-xs text-hd-muted">
      <.icon name="hero-check-circle" class="size-3.5 shrink-0 text-hd-green/80" />
      {@label}
    </li>
    """
  end
end
