defmodule IcarurssWeb.UserLive.LoginTest do
  use IcarurssWeb.ConnCase

  import Phoenix.LiveViewTest
  import Icarurss.AccountsFixtures

  describe "login page" do
    test "renders login page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "Log in"
      assert html =~ "Account registration is invite-only"
      assert html =~ "Username"
      assert html =~ "Password"
    end
  end

  describe "login navigation" do
    setup do
      original = Application.get_env(:icarurss, :registration_enabled)
      Application.put_env(:icarurss, :registration_enabled, true)
      on_exit(fn -> Application.put_env(:icarurss, :registration_enabled, original) end)
      :ok
    end

    test "redirects to registration page when the Sign up link is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      {:ok, _login_live, login_html} =
        lv
        |> element("main a", "Sign up")
        |> render_click()
        |> follow_redirect(conn, ~p"/users/register")

      assert login_html =~ "Register"
    end
  end

  describe "re-authentication (sudo mode)" do
    setup %{conn: conn} do
      user = user_fixture()
      %{user: user, conn: log_in_user(conn, user)}
    end

    test "shows login page with username filled in", %{conn: conn, user: user} do
      {:ok, lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "You need to re-authenticate"
      refute html =~ "Sign up"
      assert has_element?(lv, ~s(input[name="user[username]"]))
      assert render(lv) =~ user.username
    end
  end
end
