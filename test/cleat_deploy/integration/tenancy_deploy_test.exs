defmodule CleatDeploy.Integration.TenancyDeployTest do
  @moduledoc """
  End-to-end tenancy visibility for the seeded Trip Planner deploy test.
  """
  use CleatDeployWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias CleatDeploy.{Accounts, Apps, Seeds, TenancyFixtures}

  @tag :integration
  test "matheus sees trip-planner on dashboard; other user sees empty tenant", %{conn: _conn} do
    {:ok, %{user: matheus, scope: matheus_scope}} = Seeds.run()

    matheus_conn = log_in_user(build_conn(), matheus)
    {:ok, matheus_view, matheus_html} = live(matheus_conn, ~p"/")

    assert matheus_html =~ "Trip Planner"
    assert has_element?(matheus_view, "#dashboard")

    other = TenancyFixtures.scope_fixture()
    other_conn = log_in_user(build_conn(), other.user)
    {:ok, other_view, other_html} = live(other_conn, ~p"/")

    refute other_html =~ "Trip Planner"
    assert has_element?(other_view, "#dashboard")

    assert Accounts.get_scope_for_user(matheus).tenant.id == matheus_scope.tenant.id
    refute Enum.any?(Apps.list_apps(other), &(&1.slug == "trip-planner"))
  end
end
