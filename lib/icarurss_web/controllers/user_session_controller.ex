defmodule IcarurssWeb.UserSessionController do
  use IcarurssWeb, :controller

  alias Icarurss.Accounts
  alias IcarurssWeb.UserAuth

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  # username + password login
  defp create(conn, %{"user" => user_params}, info) do
    username = Map.get(user_params, "username", "")
    password = Map.get(user_params, "password", "")

    if user = Accounts.get_user_by_username_and_password(username, password) do
      conn
      |> put_flash(:info, info)
      |> UserAuth.log_in_user(user, user_params)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the username is registered.
      conn
      |> put_flash(:error, "Invalid username or password")
      |> put_flash(:username, String.slice(username, 0, 160))
      |> redirect(to: ~p"/users/log-in")
    end
  end

  def update_password(conn, %{"user" => user_params} = params) do
    user = conn.assigns.current_scope.user

    case Accounts.update_user_password(user, user_params, require_current_password: true) do
      {:ok, {_user, expired_tokens}} ->
        # disconnect all existing LiveViews with old sessions
        UserAuth.disconnect_sessions(expired_tokens)

        conn
        |> put_session(:user_return_to, ~p"/users/settings/password")
        |> create(params, "Password updated successfully!")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Could not update password.")
        |> redirect(to: ~p"/users/settings/password")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
