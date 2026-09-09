defmodule CleatDeployWeb.UserRegistrationControllerTest do
  use CleatDeployWeb.ConnCase

  import CleatDeploy.AccountsFixtures

  describe "GET /users/register" do
    test "renders signup page with form and branding", %{conn: conn} do
      conn = get(conn, ~p"/users/register")
      response = html_response(conn, 200)

      assert response =~ "Create your account"
      assert response =~ "Cleat"
      assert response =~ ~s(id="signup-form")
      assert response =~ ~s(type="email")
      assert response =~ ~s(type="password")
      assert response =~ "Password"
      assert response =~ "Confirm password"
      refute response =~ "magic link"
      assert response =~ "Create account"
      assert response =~ ~p"/users/log-in"
    end

    test "renders link to log in for existing users", %{conn: conn} do
      conn = get(conn, ~p"/users/register")
      response = html_response(conn, 200)

      assert response =~ "Already have an account?"
      assert response =~ "Log in"
    end

    test "redirects if already logged in", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/users/register")

      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "POST /users/register" do
    test "creates account and logs the user in", %{conn: conn} do
      email = unique_user_email()
      password = valid_user_password()

      conn =
        post(conn, ~p"/users/register", %{
          "user" => %{
            "email" => email,
            "password" => password,
            "password_confirmation" => password
          }
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
      assert conn.assigns.flash["info"] =~ "Account created successfully"
    end

    test "renders errors for invalid email", %{conn: conn} do
      conn =
        post(conn, ~p"/users/register", %{
          "user" => %{
            "email" => "with spaces",
            "password" => valid_user_password(),
            "password_confirmation" => valid_user_password()
          }
        })

      response = html_response(conn, 200)
      assert response =~ "Create your account"
      assert response =~ ~s(id="signup-form")
      assert response =~ "must have the @ sign and no spaces"
    end

    test "renders errors for short password", %{conn: conn} do
      conn =
        post(conn, ~p"/users/register", %{
          "user" => %{
            "email" => unique_user_email(),
            "password" => "short",
            "password_confirmation" => "short"
          }
        })

      response = html_response(conn, 200)
      assert response =~ "should be at least 12 character(s)"
    end

    test "renders errors for password mismatch", %{conn: conn} do
      conn =
        post(conn, ~p"/users/register", %{
          "user" => %{
            "email" => unique_user_email(),
            "password" => valid_user_password(),
            "password_confirmation" => "different password!"
          }
        })

      response = html_response(conn, 200)
      assert response =~ "does not match password"
    end

    test "renders errors for duplicate email", %{conn: conn} do
      %{email: email} = user_fixture()

      conn =
        post(conn, ~p"/users/register", %{
          "user" => %{
            "email" => email,
            "password" => valid_user_password(),
            "password_confirmation" => valid_user_password()
          }
        })

      response = html_response(conn, 200)
      assert response =~ "Create your account"
      assert response =~ "has already been taken"
    end

    test "preserves email on validation error", %{conn: conn} do
      email = "invalid-email"

      conn =
        post(conn, ~p"/users/register", %{
          "user" => %{
            "email" => email,
            "password" => valid_user_password(),
            "password_confirmation" => valid_user_password()
          }
        })

      response = html_response(conn, 200)

      assert response =~ ~s(value="#{email}")
    end
  end
end
