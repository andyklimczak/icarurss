defmodule Mix.Tasks.Users.ResetPassword do
  @shortdoc "Resets a user's password and prints the generated value"
  @moduledoc """
  Resets a user's password with a generated strong password.

      mix users.reset_password username
  """

  use Mix.Task

  alias Icarurss.Accounts
  alias Icarurss.Accounts.User
  alias Mix.Tasks.Users.Helpers

  @password_bytes 24

  @impl true
  def run(args) do
    Helpers.disable_endpoint_server()
    Mix.Task.run("app.start")

    with {:ok, username} <- parse_username(args),
         {:ok, %User{} = user} <- fetch_user(username),
         password <- generate_password(),
         {:ok, {updated_user, _expired_tokens}} <- reset_password(user, password) do
      Mix.shell().info("Password reset for username=#{updated_user.username}.")
      Mix.shell().info("New password: #{password}")
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        Mix.raise("Could not reset password: #{inspect(changeset.errors)}")

      {:error, reason} ->
        Mix.raise(reason)
    end
  end

  defp parse_username([username]) when is_binary(username) do
    normalized_username =
      username
      |> String.trim()
      |> String.downcase()

    if normalized_username == "" do
      {:error, "Username is required. Usage: mix users.reset_password username"}
    else
      {:ok, normalized_username}
    end
  end

  defp parse_username(_args) do
    {:error, "Username is required. Usage: mix users.reset_password username"}
  end

  defp fetch_user(username) do
    case Accounts.get_user_by_username(username) do
      %User{} = user -> {:ok, user}
      nil -> {:error, "User #{username} was not found."}
    end
  end

  defp generate_password do
    @password_bytes
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp reset_password(%User{} = user, password) do
    Accounts.update_user_password(user, %{
      password: password,
      password_confirmation: password
    })
  end
end
