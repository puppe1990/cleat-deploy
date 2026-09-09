defmodule CleatDeploy.Accounts.Tenant do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "tenants" do
    field :name, :string
    field :slug, :string

    has_many :memberships, CleatDeploy.Accounts.TenantMembership
    has_many :servers, CleatDeploy.Servers.Server
    has_many :apps, CleatDeploy.Apps.App

    timestamps(type: :utc_datetime)
  end

  def changeset(tenant, attrs) do
    tenant
    |> cast(attrs, [:name, :slug])
    |> validate_required([:name, :slug])
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/, message: "must be lowercase slug")
    |> unique_constraint(:slug)
  end
end
