defmodule CleatDeployWeb.Plugs.CacheBodyReader do
  @moduledoc false

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        {:ok, body, Plug.Conn.put_private(conn, :raw_body, body)}

      other ->
        other
    end
  end
end
