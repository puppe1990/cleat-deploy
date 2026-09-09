defmodule CleatDeploy.Accounts.TenantMembership do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias CleatDeploy.Accounts.{Tenant, User}

  @roles ~w(owner admin member)

  schema "tenant_memberships" do
    field :role, :string, default: "owner"

    belongs_to :user, User
    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime)
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role, :user_id, :tenant_id])
    |> validate_required([:role, :user_id, :tenant_id])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:user_id, :tenant_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:tenant_id)
  end
end
