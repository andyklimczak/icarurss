defmodule Mix.Tasks.Users.ResetPasswordTest do
  use Icarurss.DataCase, async: false

  alias Icarurss.Accounts

  setup do
    Mix.Task.reenable("users.reset_password")

    previous_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(previous_shell)
    end)

    :ok
  end

  test "resets an existing user password" do
    {:ok, user} =
      Accounts.register_user_with_password(%{
        username: "target_user",
        password: "old target password",
        password_confirmation: "old target password"
      })

    Mix.Tasks.Users.ResetPassword.run(["target_user"])

    assert_received {:mix_shell, :info, ["Password reset for username=target_user."]}
    assert_received {:mix_shell, :info, [password_line]}

    assert "New password: " <> generated_password = IO.iodata_to_binary(password_line)
    assert byte_size(generated_password) >= 32

    refute Accounts.get_user_by_username_and_password("target_user", "old target password")
    assert Accounts.get_user_by_username_and_password("target_user", generated_password)
    assert user.id == Accounts.get_user_by_username("target_user").id
  end

  test "raises a clear error when the target user does not exist" do
    assert_raise Mix.Error, ~r/User missing_user was not found/, fn ->
      Mix.Tasks.Users.ResetPassword.run(["missing_user"])
    end
  end

  test "raises a clear error for invalid options" do
    assert_raise Mix.Error, ~r/Username is required/, fn ->
      Mix.Tasks.Users.ResetPassword.run(["--as", "member_actor"])
    end
  end

  test "requires a username argument" do
    assert_raise Mix.Error, ~r/Username is required/, fn ->
      Mix.Tasks.Users.ResetPassword.run([])
    end
  end
end
