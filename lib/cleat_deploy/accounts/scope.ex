defmodule CleatDeploy.Accounts.Scope do
  @moduledoc """
  Caller scope for multi-tenant authorization and query isolation.
  """

  alias CleatDeploy.Accounts.{Tenant, User}

  defstruct user: nil, tenant: nil, role: nil

  @doc """
  Builds a scope for the given user and tenant.
  """
  def for_user(%User{} = user, %Tenant{} = tenant, role \\ "owner") do
    %__MODULE__{user: user, tenant: tenant, role: role}
  end

  def for_user(%User{} = user) do
    CleatDeploy.Accounts.get_scope_for_user(user)
  end

  def for_user(nil), do: nil
end
