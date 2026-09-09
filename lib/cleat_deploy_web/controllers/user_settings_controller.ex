defmodule CleatDeployWeb.UserSettingsController do
  use CleatDeployWeb, :controller

  alias CleatDeploy.{Accounts, Apps, Servers}
  plug :assign_panel_counts
  plug :assign_settings_forms

  def edit(conn, _params) do
    render(conn, :edit)
  end

  def update(conn, %{"action" => "update_email"} = params) do
    %{"user" => user_params} = params
    user = conn.assigns.current_scope.user

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        conn
        |> put_flash(
          :info,
          "A link to confirm your email change has been sent to the new address."
        )
        |> redirect(to: ~p"/users/settings")

      changeset ->
        render(conn, :edit, email_form: Phoenix.Component.to_form(%{changeset | action: :insert}))
    end
  end

  def update(conn, %{"action" => "update_password"} = params) do
    %{"user" => user_params} = params
    user = conn.assigns.current_scope.user
    current_token = get_session(conn, :user_token)

    case Accounts.update_user_password(user, user_params, keep_session_token: current_token) do
      {:ok, {_user, _}} ->
        conn
        |> put_flash(:info, "Password updated successfully.")
        |> redirect(to: ~p"/users/settings")

      {:error, changeset} ->
        render(conn, :edit, password_form: Phoenix.Component.to_form(changeset))
    end
  end

  def confirm_email(conn, %{"token" => token}) do
    case Accounts.update_user_email(conn.assigns.current_scope.user, token) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Email changed successfully.")
        |> redirect(to: ~p"/users/settings")

      {:error, _} ->
        conn
        |> put_flash(:error, "Email change link is invalid or it has expired.")
        |> redirect(to: ~p"/users/settings")
    end
  end

  defp assign_panel_counts(conn, _opts) do
    scope = conn.assigns.current_scope
    servers = Servers.list_servers(scope)
    apps = Apps.list_apps(scope)

    conn
    |> assign(:server_count, length(servers))
    |> assign(:app_count, length(apps))
  end

  defp assign_settings_forms(conn, _opts) do
    user = conn.assigns.current_scope.user

    conn
    |> assign(:email_form, user |> Accounts.change_user_email() |> Phoenix.Component.to_form())
    |> assign(
      :password_form,
      user |> Accounts.change_user_password() |> Phoenix.Component.to_form()
    )
  end
end
