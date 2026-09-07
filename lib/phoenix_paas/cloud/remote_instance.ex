defmodule PhoenixPaas.Cloud.RemoteInstance do
  @moduledoc false

  alias PhoenixPaas.AWS.Lightsail.InstanceSpec

  defstruct [:provider, :name, :public_ip, :region, :spec]

  @type t :: %__MODULE__{
          provider: String.t(),
          name: String.t(),
          public_ip: String.t() | nil,
          region: String.t() | nil,
          spec: InstanceSpec.t()
        }

  def from_spec(provider, %InstanceSpec{} = spec, default_region)
      when is_binary(provider) and is_binary(default_region) do
    %__MODULE__{
      provider: provider,
      name: spec.name,
      public_ip: spec.public_ip,
      region: spec.region || default_region,
      spec: spec
    }
  end
end
