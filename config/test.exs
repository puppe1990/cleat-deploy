import Config

config :swoosh, :api_client, false

config :phoenix_paas, PhoenixPaas.Mailer, adapter: Swoosh.Adapters.Test

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :phoenix_paas, PhoenixPaas.Repo,
  database: Path.expand("../phoenix_paas_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :phoenix_paas, PhoenixPaasWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "3l7wR1Z+aIhEaOKcl7otQbgdMIK7pDQRgLvpCCd0DcS/5eQoze+H+FQKo603DYKu",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

config :phoenix_paas, :auto_deploy_health_on_boot, false
config :phoenix_paas, :dns_resolver, PhoenixPaas.Deploy.DnsStub

config :phoenix_paas, Oban,
  engine: Oban.Engines.Lite,
  testing: :manual,
  notifier: Oban.Notifiers.Isolated

config :phoenix_paas, :deploy_runner, PhoenixPaas.Deploy.RunnerMock
config :phoenix_paas, :lightsail_client, PhoenixPaas.AWS.LightsailMock
config :phoenix_paas, :hetzner_client, PhoenixPaas.HetznerMock
config :phoenix_paas, :runtime_logs, PhoenixPaas.Apps.RuntimeLogsStub
config :phoenix_paas, :runtime_memory, PhoenixPaas.Apps.RuntimeMemoryStub

config :phoenix_paas, PhoenixPaas.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "v1", key: :crypto.hash(:sha256, "phoenix-paas-test-vault-v1")
    }
  ]
