defmodule IcarurssWeb.UserLive.SettingsTest do
  use IcarurssWeb.ConnCase

  alias Icarurss.Accounts
  alias Icarurss.Reader
  import Phoenix.LiveViewTest
  import Icarurss.AccountsFixtures

  describe "Settings page" do
    setup do
      original_dev_routes = Application.get_env(:icarurss, :dev_routes, false)

      on_exit(fn ->
        Application.put_env(:icarurss, :dev_routes, original_dev_routes)
      end)

      :ok
    end

    test "renders reader settings page", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings/reader")

      assert html =~ "Account Settings"
      assert html =~ "Username"
      assert html =~ "Save Reader Settings"
      refute html =~ "Save Password"
    end

    test "renders password settings page", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings/password")

      assert html =~ "Account Settings"
      assert html =~ "Username"
      assert html =~ "Save Password"
      refute html =~ "Save Reader Settings"
    end

    test "renders OPML settings page", %{conn: conn} do
      Application.put_env(:icarurss, :dev_routes, false)

      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings/opml")

      assert html =~ "Account Settings"
      assert html =~ "Export OPML"
      assert html =~ "Import OPML"
      refute html =~ "Delete All Feeds and Articles"
      refute html =~ "Save Password"
      refute html =~ "Save Reader Settings"
    end

    test "renders development reset button on OPML settings page when enabled", %{conn: conn} do
      Application.put_env(:icarurss, :dev_routes, true)

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings/opml")

      assert has_element?(lv, "#reset-opml-data-form")
      assert has_element?(lv, "#reset-opml-data-button")
    end

    test "renders username settings page", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings/username")

      assert html =~ "Account Settings"
      assert html =~ "Username"
      assert html =~ "Save Username"
      refute html =~ "Save Reader Settings"
      refute html =~ "Save Password"
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/users/settings/reader")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "allows accessing password settings even when user is not in sudo mode", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture(),
          token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
        )
        |> live(~p"/users/settings/password")

      assert html =~ "Save Password"
    end

    test "switches settings tabs via live patch", %{conn: conn} do
      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings/reader")

      lv
      |> element(~s(a[href="/users/settings/username"]))
      |> render_click()

      assert_patch(lv, ~p"/users/settings/username")
      assert has_element?(lv, "#username_form")
    end
  end

  describe "update password form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "updates the user password", %{conn: conn, user: user} do
      new_password = "this is a much newer password"

      {:ok, lv, _html} = live(conn, ~p"/users/settings/password")

      form =
        form(lv, "#password_form", %{
          "user" => %{
            "username" => user.username,
            "current_password" => valid_user_password(),
            "password" => new_password,
            "password_confirmation" => new_password
          }
        })

      render_submit(form)

      new_password_conn = follow_trigger_action(form, conn)

      assert redirected_to(new_password_conn) == ~p"/users/settings/password"

      assert get_session(new_password_conn, :user_token) != get_session(conn, :user_token)

      assert Phoenix.Flash.get(new_password_conn.assigns.flash, :info) =~
               "Password updated successfully"

      assert Accounts.get_user_by_username_and_password(user.username, new_password)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings/password")

      result =
        lv
        |> element("#password_form")
        |> render_change(%{
          "user" => %{
            "current_password" => valid_user_password(),
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })

      assert result =~ "Save Password"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings/password")

      result =
        lv
        |> form("#password_form", %{
          "user" => %{
            "current_password" => valid_user_password(),
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })
        |> render_submit()

      assert result =~ "Save Password"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
    end

    test "renders errors with invalid current password", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings/password")

      result =
        lv
        |> form("#password_form", %{
          "user" => %{
            "current_password" => "wrong password",
            "password" => "this is a much newer password",
            "password_confirmation" => "this is a much newer password"
          }
        })
        |> render_submit()

      assert result =~ "Current password"
      assert result =~ "is not valid"
    end
  end

  describe "reader settings form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "updates reader timezone", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings/reader")

      lv
      |> form("#reader_settings_form", %{
        "reader_setting" => %{"timezone" => "America/New_York", "article_open_mode" => "new_tab"}
      })
      |> render_submit()

      setting = Reader.get_or_create_reader_setting(user)
      assert setting.timezone == "America/New_York"
      assert setting.article_open_mode == :new_tab
    end

    test "renders timezone dropdown options", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings/reader")

      html = render(lv)
      assert html =~ "reader_setting_timezone"
      assert html =~ "UTC"
      assert html =~ "America/New_York"
    end

    test "renders validation errors for invalid timezone when posted directly", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings/reader")

      result =
        render_submit(lv, "update_reader_settings", %{
          "reader_setting" => %{
            "timezone" => "Not/A_Real_Zone",
            "article_open_mode" => "three_column"
          }
        })

      assert result =~ "is not a valid IANA timezone"
    end
  end

  describe "username settings form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "updates username", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings/username")

      lv
      |> form("#username_form", %{"user" => %{"username" => "new_handle"}})
      |> render_submit()

      updated = Accounts.get_user!(user.id)
      assert updated.username == "new_handle"
    end

    test "validates username uniqueness", %{conn: conn} do
      _existing = user_fixture(%{username: "taken_name"})
      user = user_fixture()

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/settings/username")

      result =
        lv
        |> form("#username_form", %{"user" => %{"username" => "taken_name"}})
        |> render_submit()

      assert result =~ "has already been taken"
    end
  end
end
