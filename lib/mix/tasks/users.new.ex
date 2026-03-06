defmodule Mix.Tasks.Users.New do
  @shortdoc "Creates or updates a user with username/password"
  @moduledoc """
  Creates or updates a user via interactive prompts.

      mix users.new
      mix users.new --as admin_username
  """

  use Mix.Task

  alias Icarurss.Accounts
  alias Icarurss.Accounts.User

  @impl true
  def run(args) do
    disable_endpoint_server()
    Mix.Task.run("app.start")

    with {:ok, actor} <- parse_actor(args),
         :ok <- Accounts.authorize_user_management(actor) do
      username = prompt_username()
      password = prompt_password()
      role = prompt_role()

      case Accounts.upsert_managed_user(actor, username, password, role) do
        {:ok, user} ->
          Mix.shell().info("User saved username=#{user.username} role=#{user.role}.")

        {:error, %Ecto.Changeset{} = changeset} ->
          Mix.raise("Could not save user: #{inspect(changeset.errors)}")

        {:error, reason} ->
          Mix.raise("Could not save user: #{inspect(reason)}")
      end
    else
      {:error, reason} ->
        Mix.raise(reason)
    end
  end

  defp disable_endpoint_server do
    endpoint_config = Application.get_env(:icarurss, IcarurssWeb.Endpoint, [])

    Application.put_env(
      :icarurss,
      IcarurssWeb.Endpoint,
      Keyword.put(endpoint_config, :server, false)
    )
  end

  defp parse_actor(args) do
    {opts, _argv, invalid} = OptionParser.parse(args, strict: [as: :string])

    case invalid do
      [] ->
        resolve_actor(opts[:as])

      _ ->
        {:error, "Invalid options. Usage: mix users.new [--as admin_username]"}
    end
  end

  defp resolve_actor(nil), do: {:ok, nil}

  defp resolve_actor(actor_username) when is_binary(actor_username) do
    normalized_username = String.trim(actor_username)

    cond do
      normalized_username == "" ->
        {:error, "Option --as requires an admin username."}

      true ->
        case Accounts.get_user_by_username(normalized_username) do
          %User{} = actor -> {:ok, actor}
          nil -> {:error, "Admin actor #{normalized_username} was not found."}
        end
    end
  end

  defp prompt_username do
    username =
      Mix.shell().prompt("Username: ")
      |> String.trim()
      |> String.downcase()

    if String.match?(username, ~r/^[a-z0-9_]{3,40}$/) do
      username
    else
      Mix.shell().error(
        "Username must be 3-40 chars of lowercase letters, numbers, or underscores."
      )

      prompt_username()
    end
  end

  defp prompt_password do
    password = prompt_secret("Password (min 12 chars): ")
    confirmation = prompt_secret("Confirm password: ")

    cond do
      String.length(password) < 12 ->
        Mix.shell().error("Password must be at least 12 characters.")
        prompt_password()

      password != confirmation ->
        Mix.shell().error("Password confirmation does not match.")
        prompt_password()

      true ->
        password
    end
  end

  defp prompt_secret(prompt) do
    try do
      case :io.get_password(String.to_charlist(prompt)) do
        :eof ->
          Mix.raise("Input aborted.")

        password when is_list(password) ->
          password
          |> List.to_string()
          |> String.trim()
      end
    rescue
      FunctionClauseError ->
        Mix.shell().prompt(prompt) |> String.trim()
    end
  end

  defp prompt_role do
    role =
      Mix.shell().prompt("Role [member/admin] (default: member): ")
      |> String.trim()
      |> String.downcase()

    case role do
      "" ->
        :member

      "member" ->
        :member

      "admin" ->
        :admin

      _ ->
        Mix.shell().error("Role must be either 'member' or 'admin'.")
        prompt_role()
    end
  end
end
