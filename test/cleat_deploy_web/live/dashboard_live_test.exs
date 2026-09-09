defmodule CleatDeployWeb.DashboardLiveTest do
  use CleatDeployWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias CleatDeploy.HetznerMock
  alias CleatDeploy.TenancyFixtures
  alias CleatDeployWeb.UserAuth

  setup :register_and_log_in_user

  test "redirects when not logged in" do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(build_conn(), ~p"/")
  end

  test "renders dashboard when only remember-me cookie is present", %{user: user} do
    logged_in_conn =
      build_conn()
      |> Map.replace!(:secret_key_base, CleatDeployWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})
      |> fetch_cookies()
      |> UserAuth.log_in_user(user, %{"remember_me" => "true"})

    %{value: signed_token} = logged_in_conn.resp_cookies["_cleat_deploy_web_user_remember_me"]

    conn =
      logged_in_conn
      |> recycle()
      |> Map.replace!(:secret_key_base, CleatDeployWeb.Endpoint.config(:secret_key_base))
      |> put_req_cookie("_cleat_deploy_web_user_remember_me", signed_token)
      |> init_test_session(%{user_remember_me: true})

    refute get_session(conn, :user_token)

    {:ok, view, html} = live(conn, ~p"/")
    assert has_element?(view, "#dashboard")
    assert has_element?(view, "#theme-toggle")
    assert has_element?(view, "#app-shell")
    assert has_element?(view, "#app-sidebar")
    assert has_element?(view, "#app-sidebar-actions")
    assert has_element?(view, "#app-footer")
    assert has_element?(view, "#nav-dashboard")
    assert has_element?(view, "#nav-servers")
    assert has_element?(view, "#nav-apps")
    assert html =~ "Cleat"
  end

  test "renders dashboard when only user_id is present in session", %{user: user} do
    conn =
      build_conn()
      |> init_test_session(%{user_id: user.id})

    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#dashboard")
  end

  test "renders dashboard overview for tenant", %{conn: conn, scope: scope} do
    server =
      TenancyFixtures.server_fixture(scope, %{name: "lightsail-1", host_ip: "100.59.80.29"})

    TenancyFixtures.app_fixture(scope, server, %{
      name: "Trip Planner",
      slug: "trip-planner",
      github_repo: "puppe1990/trip-planner-ia-phx",
      host: "trip.gestaobem.com"
    })

    {:ok, view, html} = live(conn, ~p"/")
    assert has_element?(view, "#dashboard")
    assert html =~ "Configured apps"
    refute has_element?(view, "#dashboard-hero")
    refute html =~ "No Kubernetes Overheads"
    refute html =~ "HETZNER + LIGHTSAIL"
    assert has_element?(view, "#server-charts")
    assert has_element?(view, "#chart-cpu")
    assert has_element?(view, "#chart-network")
    assert has_element?(view, "#chart-runtimes")
    assert has_element?(view, "#chart-deploys")
    assert has_element?(view, "#chart-deploys-plot")
    refute has_element?(view, "#dashboard-apps-table")
    refute has_element?(view, "#apps-table")
    refute html =~ "Registered Phoenix Applications"
  end

  test "plots hetzner cpu samples on the dashboard", %{conn: conn, scope: scope} do
    TenancyFixtures.server_fixture(scope, %{
      name: "gestaobem-cx33",
      provider: "hetzner",
      region: "fsn1",
      aws_instance_name: "gestaobem-cx33",
      bundle_name: "CX33",
      cpu_count: 4,
      ram_mb: 8192,
      disk_gb: 80,
      instance_status: "running"
    })

    stub(HetznerMock, :get_metrics, fn "fsn1", "gestaobem-cx33", _start, _end ->
      {:ok,
       %{
         cpu: [%{t: 1, v: 8.0}, %{t: 2, v: 21.5}, %{t: 3, v: 14.0}],
         network_in: [%{t: 1, v: 1_000.0}, %{t: 2, v: 2_000.0}, %{t: 3, v: 1_500.0}],
         network_out: [%{t: 1, v: 500.0}, %{t: 2, v: 800.0}, %{t: 3, v: 600.0}]
       }}
    end)

    {:ok, view, html} = live(conn, ~p"/")
    assert has_element?(view, "#chart-cpu")
    assert has_element?(view, "#chart-cpu-plot")
    assert has_element?(view, "#chart-network-plot")
    assert html =~ "gestaobem-cx33"
    assert html =~ "CX33"
    rendered = render(view)
    assert rendered =~ "14.0%"
    assert rendered =~ "21.5%"
    assert rendered =~ "data-points"
    assert has_element?(view, "#chart-cpu-current", "14.0%")
    refute render(view) =~ "Live · 100% = 1 vCPU"
  end

  test "live tick keeps hetzner current for a remote server", %{conn: conn, scope: scope} do
    TenancyFixtures.server_fixture(scope, %{
      name: "gestaobem-cx33",
      provider: "hetzner",
      region: "fsn1",
      aws_instance_name: "gestaobem-cx33",
      host_ip: "10.0.0.1",
      cpu_count: 4,
      instance_status: "running"
    })

    stub(HetznerMock, :get_metrics, fn "fsn1", "gestaobem-cx33", _start, _end ->
      {:ok,
       %{
         cpu: [%{t: 1, v: 8.0}, %{t: 2, v: 14.0}],
         network_in: [%{t: 1, v: 1_000.0}, %{t: 2, v: 1_500.0}],
         network_out: [%{t: 1, v: 500.0}, %{t: 2, v: 600.0}]
       }}
    end)

    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#chart-cpu-current", "14.0%")

    send(view.pid, :tick_live)
    _ = :sys.get_state(view.pid)
    assert has_element?(view, "#chart-cpu-current", "14.0%")

    send(view.pid, :tick_hetzner)
    _ = :sys.get_state(view.pid)
    assert has_element?(view, "#chart-cpu")
    assert has_element?(view, "#chart-cpu-current", "14.0%")
  end

  test "does not show other tenant apps", %{conn: conn, scope: scope} do
    other = TenancyFixtures.scope_fixture()
    server = TenancyFixtures.server_fixture(other)

    TenancyFixtures.app_fixture(other, server, %{
      name: "Secret App",
      slug: "secret",
      github_repo: "other/secret",
      host: "secret.example.com"
    })

    {:ok, view, _html} = live(conn, ~p"/")
    refute render(view) =~ "Secret App"
    assert scope.tenant.id != other.tenant.id
  end
end
