defmodule IcarurssWeb.UserLive.RegistrationTest do
  use IcarurssWeb.ConnCase

  import Phoenix.LiveViewTest
  import Icarurss.AccountsFixtures

  describe "Registration page" do
    test "redirects to login when self-service registration is disabled", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: path, flash: flash}}} =
               live(conn, ~p"/users/register")

      assert path == ~p"/users/log-in"
      assert %{"error" => "Registration is disabled. Ask an admin for an invite."} = flash
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/register")
        |> follow_redirect(conn, ~p"/")

      assert {:ok, _conn} = result
    end

    test "renders errors for invalid data when registration is enabled", %{conn: conn} do
      original = Application.get_env(:icarurss, :registration_enabled)
      Application.put_env(:icarurss, :registration_enabled, true)
      on_exit(fn -> Application.put_env(:icarurss, :registration_enabled, original) end)

      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(
          user: %{
            "username" => "Bad Name",
            "password" => "too short",
            "password_confirmation" => "mismatch"
          }
        )

      assert result =~ "Register"
      assert result =~ "must contain only lowercase letters"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
    end
  end

  describe "register user" do
    setup do
      original = Application.get_env(:icarurss, :registration_enabled)
      Application.put_env(:icarurss, :registration_enabled, true)
      on_exit(fn -> Application.put_env(:icarurss, :registration_enabled, original) end)
      :ok
    end

    test "creates account and redirects to login", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      username = unique_username()

      form =
        form(lv, "#registration_form",
          user: %{
            "username" => username,
            "password" => valid_user_password(),
            "password_confirmation" => valid_user_password()
          }
        )

      {:ok, _lv, html} =
        render_submit(form)
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "Account created for #{username}. You can now log in."
    end

    test "renders errors for duplicated username", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> form("#registration_form",
          user: %{
            "username" => user.username,
            "password" => valid_user_password(),
            "password_confirmation" => valid_user_password()
          }
        )
        |> render_submit()

      assert result =~ "has already been taken"
    end
  end

  describe "registration navigation" do
    setup do
      original = Application.get_env(:icarurss, :registration_enabled)
      Application.put_env(:icarurss, :registration_enabled, true)
      on_exit(fn -> Application.put_env(:icarurss, :registration_enabled, original) end)
      :ok
    end

    test "redirects to login page when the Log in button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      {:ok, _login_live, login_html} =
        lv
        |> element("main a", "Log in")
        |> render_click()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert login_html =~ "Log in"
    end
  end
end
