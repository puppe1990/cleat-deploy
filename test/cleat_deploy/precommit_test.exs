defmodule CleatDeploy.PrecommitTest do
  use ExUnit.Case, async: false

  test "precommit alias is configured" do
    aliases = CleatDeploy.MixProject.project() |> Keyword.fetch!(:aliases)
    assert is_list(Keyword.fetch!(aliases, :precommit))
  end
end
