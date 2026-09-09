defmodule CleatDeployWeb.Router do
  use CleatDeployWeb, :router

  import CleatDeployWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CleatDeployWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :github_webhook do
    plug :accepts, ["json"]
  end

  scope "/webhooks", CleatDeployWeb do
    pipe_through :github_webhook

    post "/github", GithubWebhookController, :create
  end

  scope "/", CleatDeployWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :authenticated,
      on_mount: [
        {CleatDeployWeb.UserAuth, :mount_current_scope},
        {CleatDeployWeb.UserAuth, :require_authenticated},
        {CleatDeployWeb.PaasMount, :default}
      ] do
      live "/", DashboardLive, :index
      live "/servers", ServerLive.Index, :index
      live "/servers/new", ServerLive.Index, :new
      live "/servers/:id", ServerLive.Show, :show
      live "/apps", AppLive.Index, :index
      live "/apps/new", AppLive.Index, :new
      live "/apps/:id", AppLive.Show, :show
      live "/apps/:app_id/deployments", AppLive.Deployments, :index
    end
  end

  if Application.compile_env(:cleat_deploy, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: CleatDeployWeb.Telemetry
    end
  end

  ## Authentication routes

  scope "/", CleatDeployWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
  end

  scope "/", CleatDeployWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm-email/:token", UserSettingsController, :confirm_email
  end

  scope "/", CleatDeployWeb do
    pipe_through [:browser]

    get "/users/log-in", UserSessionController, :new
    get "/users/log-in/:token", UserSessionController, :confirm
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
