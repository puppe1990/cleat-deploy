defmodule CleatDeploy.Repo do
  @moduledoc false

  @adapter if Mix.env() == :prod,
             do: Ecto.Adapters.LibSql,
             else: Ecto.Adapters.SQLite3

  use Ecto.Repo,
    otp_app: :cleat_deploy,
    adapter: @adapter
end
