defmodule CleatDeploy.Deploy.DnsStub do
  @moduledoc false
  @behaviour CleatDeploy.Deploy.DnsResolver

  @impl true
  def lookup_a(_host), do: {:error, :no_a_record}
end
