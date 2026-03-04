defmodule Mix.Tasks.Users.NewTest do
  use Icarurss.DataCase, async: false

  import ExUnit.CaptureIO

  alias Icarurss.Accounts

  setup do
    Mix.Task.reenable("users.new")

    previous_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(previous_shell)
    end)

    :ok
  end

  test "creates a member user in bootstrap mode" do
    send(self(), {:mix_shell_input, :prompt, "bootstrap_member"})
    send(self(), {:mix_shell_input, :prompt, "a very strong password"})
    send(self(), {:mix_shell_input, :prompt, "a very strong password"})
    send(self(), {:mix_shell_input, :prompt, ""})

    capture_io(fn ->
      Mix.Tasks.Users.New.run([])
    end)

    user = Accounts.get_user_by_username("bootstrap_member")
    assert user.role == :member

    assert Accounts.get_user_by_username_and_password(
             "bootstrap_member",
             "a very strong password"
           )
  end

  test "updates an existing user role/password when run as admin" do
    {:ok, admin} =
      Accounts.register_user_with_password(%{
        username: "admin_actor",
        password: "an admin password",
        password_confirmation: "an admin password"
      })

    {:ok, _admin} = Accounts.update_user_role(admin, :admin)

    {:ok, target} =
      Accounts.register_user_with_password(%{
        username: "target_user",
        password: "old target password",
        password_confirmation: "old target password"
      })

    assert target.role == :member

    send(self(), {:mix_shell_input, :prompt, "target_user"})
    send(self(), {:mix_shell_input, :prompt, "new target password"})
    send(self(), {:mix_shell_input, :prompt, "new target password"})
    send(self(), {:mix_shell_input, :prompt, "admin"})

    capture_io(fn ->
      Mix.Tasks.Users.New.run(["--as", "admin_actor"])
    end)

    updated_user = Accounts.get_user!(target.id)
    assert updated_user.role == :admin
    assert Accounts.get_user_by_username_and_password("target_user", "new target password")
  end

  test "raises a clear error when non-admin actor attempts user management" do
    _member_actor =
      Accounts.register_user_with_password(%{
        username: "member_actor",
        password: "a member password",
        password_confirmation: "a member password"
      })

    send(self(), {:mix_shell_input, :prompt, "never_used"})
    send(self(), {:mix_shell_input, :prompt, "never used password"})
    send(self(), {:mix_shell_input, :prompt, "never used password"})
    send(self(), {:mix_shell_input, :prompt, ""})

    assert_raise Mix.Error, ~r/Only admin users can manage users/, fn ->
      capture_io(fn ->
        Mix.Tasks.Users.New.run(["--as", "member_actor"])
      end)
    end
  end

  test "re-prompts when password confirmation does not match" do
    send(self(), {:mix_shell_input, :prompt, "member_user"})
    send(self(), {:mix_shell_input, :prompt, "a very strong password"})
    send(self(), {:mix_shell_input, :prompt, "different password"})
    send(self(), {:mix_shell_input, :prompt, "a very strong password"})
    send(self(), {:mix_shell_input, :prompt, "a very strong password"})
    send(self(), {:mix_shell_input, :prompt, ""})

    capture_io(fn ->
      Mix.Tasks.Users.New.run([])
    end)

    assert_received {:mix_shell, :error, error_message}
    assert IO.iodata_to_binary(error_message) =~ "Password confirmation does not match."
    assert Accounts.get_user_by_username_and_password("member_user", "a very strong password")
  end
end
