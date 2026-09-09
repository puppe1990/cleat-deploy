defmodule CleatDeploy.Encrypted do
  @moduledoc false

  defmodule Binary do
    @moduledoc false
    use Cloak.Ecto.Binary, vault: CleatDeploy.Vault
  end
end
