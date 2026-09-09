defmodule CleatDeploy.Deployments.Deployment do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias CleatDeploy.Apps.App

  @statuses [:queued, :running, :success, :failed]

  schema "deployments" do
    field :git_sha, :string
    field :git_ref, :string
    field :status, Ecto.Enum, values: @statuses, default: :queued
    field :log, :string, default: ""
    field :triggered_by, :string, default: "manual"
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime

    belongs_to :app, App

    timestamps(type: :utc_datetime)
  end

  def changeset(deployment, attrs) do
    deployment
    |> cast(attrs, [
      :git_sha,
      :git_ref,
      :status,
      :log,
      :triggered_by,
      :started_at,
      :finished_at,
      :app_id
    ])
    |> validate_required([:git_sha, :app_id])
    |> foreign_key_constraint(:app_id)
  end

  def statuses, do: @statuses
end
