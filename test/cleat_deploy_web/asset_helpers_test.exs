defmodule CleatDeployWeb.AssetHelpersTest do
  use ExUnit.Case, async: true

  alias CleatDeployWeb.AssetHelpers

  test "asset_path/1 appends dev cache buster when code_reloader is enabled" do
    endpoint_config = Application.get_env(:cleat_deploy, CleatDeployWeb.Endpoint, [])
    original = Keyword.get(endpoint_config, :code_reloader)

    on_exit(fn ->
      Application.put_env(
        :cleat_deploy,
        CleatDeployWeb.Endpoint,
        Keyword.put(endpoint_config, :code_reloader, original)
      )
    end)

    Application.put_env(
      :cleat_deploy,
      CleatDeployWeb.Endpoint,
      Keyword.put(endpoint_config, :code_reloader, true)
    )

    path = AssetHelpers.asset_path("/assets/css/app.css")

    assert path =~ "/assets/css/app.css?"
    assert path =~ "t="
  end
end
