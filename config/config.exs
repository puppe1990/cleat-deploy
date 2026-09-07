# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :phoenix_paas, :scopes,
  user: [
    default: true,
    module: PhoenixPaas.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: PhoenixPaas.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :phoenix_paas,
  ecto_repos: [PhoenixPaas.Repo],
  generators: [timestamp_type: :utc_datetime]

config :phoenix_paas, :lightsail_client, PhoenixPaas.AWS.Lightsail.Stub
config :phoenix_paas, :hetzner_client, PhoenixPaas.Hetzner.Stub
config :phoenix_paas, :runtime_logs, PhoenixPaas.Apps.RuntimeLogsSsh
config :phoenix_paas, :runtime_memory, PhoenixPaas.Apps.RuntimeLogsSsh

config :phoenix_paas, :auto_deploy_health_on_boot, true

config :phoenix_paas, Oban,
  repo: PhoenixPaas.Repo,
  engine: Oban.Engines.Lite,
  prefix: false,
  notifier: Oban.Notifiers.Isolated,
  peer: Oban.Peers.Isolated,
  # Keep modest concurrency so different Lightsail hosts can deploy in parallel.
  # Same-host deploys are serialized in DeployWorker via claim_running/snooze.
  queues: [deploys: 2, maintenance: 1],
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       {"*/15 * * * *", PhoenixPaas.Workers.AutoDeployHealthWorker}
     ]}
  ],
  shutdown_grace_period: :timer.minutes(15)

# Configure the endpoint
config :phoenix_paas, PhoenixPaasWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PhoenixPaasWeb.ErrorHTML, json: PhoenixPaasWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: PhoenixPaas.PubSub,
  live_view: [signing_salt: "lEUtsEZC"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  phoenix_paas: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  phoenix_paas: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
