defmodule CleatDeploy.Accounts.TenancyTest do
  use CleatDeploy.DataCase

  alias CleatDeploy.{Apps, Servers}
  alias CleatDeploy.Accounts
  alias CleatDeploy.TenancyFixtures

  describe "register_user_with_tenant/1" do
    test "creates user, tenant, and owner membership" do
      password = "password123456"

      assert {:ok, %{user: user, tenant: tenant, membership: membership}} =
               Accounts.register_user_with_tenant(%{
                 email: "matheus.puppe@gmail.com",
                 password: password,
                 password_confirmation: password
               })

      assert user.email == "matheus.puppe@gmail.com"
      assert user.confirmed_at
      assert Accounts.User.valid_password?(user, password)
      assert tenant.slug == "matheus-puppe"
      assert membership.role == "owner"
    end
  end

  describe "tenant isolation" do
    test "servers are scoped per tenant" do
      scope_a = TenancyFixtures.scope_fixture()
      scope_b = TenancyFixtures.scope_fixture()

      {:ok, server_a} =
        Servers.create_server(scope_a, %{
          name: "tenant-a",
          host_ip: "10.0.0.1",
          ssh_user: "ubuntu",
          region: "us-east-1"
        })

      {:ok, _server_b} =
        Servers.create_server(scope_b, %{
          name: "tenant-b",
          host_ip: "10.0.0.2",
          ssh_user: "ubuntu",
          region: "us-east-1"
        })

      assert [only] = Servers.list_servers(scope_a)
      assert only.id == server_a.id
      assert length(Servers.list_servers(scope_b)) == 1
    end

    test "get_server!/2 raises for cross-tenant access" do
      scope_a = TenancyFixtures.scope_fixture()
      scope_b = TenancyFixtures.scope_fixture()

      {:ok, server} =
        Servers.create_server(scope_a, %{
          name: "private",
          host_ip: "10.0.0.9",
          ssh_user: "ubuntu",
          region: "us-east-1"
        })

      assert_raise Ecto.NoResultsError, fn ->
        Servers.get_server!(scope_b, server.id)
      end
    end

    test "apps slug is unique per tenant" do
      scope_a = TenancyFixtures.scope_fixture()
      scope_b = TenancyFixtures.scope_fixture()

      server_a = TenancyFixtures.server_fixture(scope_a)
      server_b = TenancyFixtures.server_fixture(scope_b)

      assert {:ok, _, _} =
               Apps.create_app(scope_a, %{
                 name: "Trip",
                 slug: "trip-planner",
                 github_repo: "a/trip",
                 host: "a.example.com",
                 server_id: server_a.id
               })

      assert {:ok, _, _} =
               Apps.create_app(scope_b, %{
                 name: "Trip",
                 slug: "trip-planner",
                 github_repo: "b/trip",
                 host: "b.example.com",
                 server_id: server_b.id
               })
    end
  end
end
