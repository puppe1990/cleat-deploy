defmodule CleatDeploy.Deploy.DnsResolver do
  @moduledoc false

  @callback lookup_a(String.t()) :: {:ok, [String.t()]} | {:error, atom()}
end
