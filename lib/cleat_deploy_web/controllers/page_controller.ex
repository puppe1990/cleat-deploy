defmodule CleatDeployWeb.PageController do
  use CleatDeployWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: ~p"/")
  end
end
