defmodule IcarurssWeb.UserLive.Login do
  use IcarurssWeb, :live_view

  alias Icarurss.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-4">
        <div class="text-center">
          <.header>
            <p>Log in</p>
            <:subtitle>
              <%= if @current_scope do %>
                You need to re-authenticate to perform sensitive actions on your account.
              <% else %>
                <%= if @registration_enabled do %>
                  Don't have an account? <.link
                    navigate={~p"/users/register"}
                    class="font-semibold text-brand hover:underline"
                    phx-no-format
                  >Sign up</.link>.
                <% else %>
                  Account registration is invite-only.
                <% end %>
              <% end %>
            </:subtitle>
          </.header>
        </div>

        <.form for={@form} id="login_form" action={~p"/users/log-in"}>
          <.input
            field={@form[:username]}
            type="text"
            label="Username"
            autocomplete="username"
            required
            readonly={@reauthenticate?}
            phx-mounted={JS.focus()}
          />

          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            autocomplete="current-password"
            required
          />

          <.input
            field={@form[:remember_me]}
            type="checkbox"
            label="Keep me logged in on this device"
          />

          <.button class="btn btn-primary w-full">
            Log in <span aria-hidden="true">→</span>
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    current_user =
      case socket.assigns.current_scope do
        %{user: user} -> user
        _ -> nil
      end

    username =
      Phoenix.Flash.get(socket.assigns.flash, :username) ||
        (current_user && current_user.username)

    form =
      to_form(
        %{"username" => username || "", "password" => "", "remember_me" => "false"},
        as: "user"
      )

    {:ok,
     socket
     |> assign(:form, form)
     |> assign(:registration_enabled, Accounts.registration_enabled?())
     |> assign(:reauthenticate?, not is_nil(current_user))}
  end
end
