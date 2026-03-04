defmodule IcarurssWeb.UserLive.Settings do
  use IcarurssWeb, :live_view

  on_mount {IcarurssWeb.UserAuth, :require_sudo_mode}

  alias Icarurss.Accounts
  alias Icarurss.Reader

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-xl space-y-6">
        <div class="text-center">
          <.header>
            Account Settings
            <:subtitle>Manage reader preferences and account security.</:subtitle>
          </.header>
        </div>

        <div class="rounded-lg border border-zinc-200 bg-zinc-50 px-4 py-3">
          <p class="text-xs uppercase tracking-wide text-zinc-500">Username</p>
          <p class="mt-1 font-medium text-zinc-900">{@current_username}</p>
        </div>

        <nav class="flex items-center gap-2 border-b border-base-300 pb-3">
          <.link
            patch={~p"/users/settings/reader"}
            class={[
              "inline-flex items-center rounded-md border px-3 py-1.5 text-sm transition",
              if(@live_action == :reader,
                do: "border-base-300 bg-base-200 text-base-content",
                else: "border-base-300 bg-base-100 text-base-content hover:bg-base-200"
              )
            ]}
          >
            Reader Settings
          </.link>
          <.link
            patch={~p"/users/settings/opml"}
            class={[
              "inline-flex items-center rounded-md border px-3 py-1.5 text-sm transition",
              if(@live_action == :opml,
                do: "border-base-300 bg-base-200 text-base-content",
                else: "border-base-300 bg-base-100 text-base-content hover:bg-base-200"
              )
            ]}
          >
            OPML
          </.link>
          <.link
            patch={~p"/users/settings/username"}
            class={[
              "inline-flex items-center rounded-md border px-3 py-1.5 text-sm transition",
              if(@live_action == :username,
                do: "border-base-300 bg-base-200 text-base-content",
                else: "border-base-300 bg-base-100 text-base-content hover:bg-base-200"
              )
            ]}
          >
            Username
          </.link>
          <.link
            patch={~p"/users/settings/password"}
            class={[
              "inline-flex items-center rounded-md border px-3 py-1.5 text-sm transition",
              if(@live_action == :password,
                do: "border-base-300 bg-base-200 text-base-content",
                else: "border-base-300 bg-base-100 text-base-content hover:bg-base-200"
              )
            ]}
          >
            Password
          </.link>
        </nav>

        <%= cond do %>
          <% @live_action == :reader -> %>
            <.form
              for={@reader_settings_form}
              id="reader_settings_form"
              phx-change="validate_reader_settings"
              phx-submit="update_reader_settings"
            >
              <.input
                field={@reader_settings_form[:timezone]}
                type="select"
                label="Timezone"
                options={@timezone_options}
              />
              <.input
                field={@reader_settings_form[:article_open_mode]}
                type="select"
                label="Article Open Mode"
                options={[
                  {"Inline reader (3 columns)", :three_column},
                  {"Open in new tab (2 columns)", :new_tab}
                ]}
              />
              <.button variant="primary" phx-disable-with="Saving...">
                Save Reader Settings
              </.button>
            </.form>
          <% @live_action == :opml -> %>
            <div class="space-y-4">
              <div class="rounded-lg border border-base-300 bg-base-100 p-4">
                <h3 class="text-sm font-semibold text-base-content">Export</h3>
                <p class="mt-1 text-sm text-base-content/70">
                  Download your feed subscriptions and folders as an OPML file.
                </p>
                <.link
                  id="export-opml-link"
                  href={~p"/users/settings/opml/export"}
                  class="mt-3 inline-flex items-center rounded-md border border-base-300 bg-base-100 px-3 py-1.5 text-sm text-base-content transition hover:bg-base-200"
                >
                  <.icon name="hero-arrow-down-tray" class="mr-1 size-4" /> Export OPML
                </.link>
              </div>

              <div class="rounded-lg border border-base-300 bg-base-100 p-4">
                <h3 class="text-sm font-semibold text-base-content">Import</h3>
                <p class="mt-1 text-sm text-base-content/70">
                  Import feeds from an OPML file (`.opml`).
                </p>
                <.form
                  for={@import_opml_form}
                  id="import-opml-form"
                  action={~p"/users/settings/opml/import"}
                  method="post"
                  multipart
                >
                  <.input
                    field={@import_opml_form[:opml]}
                    type="file"
                    accept=".opml,.ompl,.xml,text/xml,application/xml"
                    label="OPML file"
                    required
                  />
                  <.button id="import-opml-submit" variant="primary" class="mt-2">
                    <.icon name="hero-arrow-up-tray" class="mr-1 size-4" /> Import OPML
                  </.button>
                </.form>
              </div>
            </div>
          <% @live_action == :username -> %>
            <.form
              for={@username_form}
              id="username_form"
              phx-change="validate_username"
              phx-submit="update_username"
            >
              <.input
                field={@username_form[:username]}
                type="text"
                label="Username"
                autocomplete="username"
                required
              />
              <.button variant="primary" phx-disable-with="Saving...">
                Save Username
              </.button>
            </.form>
          <% @live_action == :password -> %>
            <.form
              for={@password_form}
              id="password_form"
              action={~p"/users/update-password"}
              method="post"
              phx-change="validate_password"
              phx-submit="update_password"
              phx-trigger-action={@trigger_submit}
            >
              <input
                name="user[username]"
                type="hidden"
                id="hidden_user_username"
                autocomplete="username"
                value={@current_username}
              />
              <.input
                field={@password_form[:current_password]}
                type="password"
                label="Current password"
                autocomplete="current-password"
                required
              />
              <.input
                field={@password_form[:password]}
                type="password"
                label="New password"
                autocomplete="new-password"
                required
              />
              <.input
                field={@password_form[:password_confirmation]}
                type="password"
                label="Confirm new password"
                autocomplete="new-password"
              />
              <.button variant="primary" phx-disable-with="Saving...">
                Save Password
              </.button>
            </.form>
          <% true -> %>
            <div class="rounded-lg border border-base-300 bg-base-100 px-4 py-3 text-sm text-base-content/70">
              Select a settings section.
            </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    password_changeset =
      Accounts.change_user_password(user, %{},
        hash_password: false,
        require_current_password: true
      )

    username_changeset = Accounts.change_user_username(user, %{})
    reader_setting = Reader.get_or_create_reader_setting(user)
    reader_settings_changeset = Reader.change_reader_setting(reader_setting, %{})

    socket =
      socket
      |> assign(:current_username, user.username)
      |> assign(:reader_setting, reader_setting)
      |> assign(:reader_settings_form, to_form(reader_settings_changeset, as: :reader_setting))
      |> assign(:timezone_options, timezone_options())
      |> assign(:import_opml_form, to_form(%{}, as: :import_opml))
      |> assign(:username_form, to_form(username_changeset, as: :user))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params,
        hash_password: false,
        require_current_password: true
      )
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  @impl true
  def handle_event("validate_username", %{"user" => user_params}, socket) do
    username_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_username(user_params)
      |> Map.put(:action, :validate)
      |> to_form(as: :user)

    {:noreply, assign(socket, :username_form, username_form)}
  end

  @impl true
  def handle_event("update_username", %{"user" => user_params}, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.update_user_username(user, user_params) do
      {:ok, updated_user} ->
        username_form = updated_user |> Accounts.change_user_username(%{}) |> to_form(as: :user)

        {:noreply,
         socket
         |> assign(:current_username, updated_user.username)
         |> assign(:current_scope, %{socket.assigns.current_scope | user: updated_user})
         |> assign(:username_form, username_form)
         |> put_flash(:info, "Username updated successfully.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :username_form, to_form(changeset, as: :user))}
    end
  end

  @impl true
  def handle_event("validate_reader_settings", %{"reader_setting" => params}, socket) do
    reader_settings_form =
      socket.assigns.reader_setting
      |> Reader.change_reader_setting(params)
      |> Map.put(:action, :validate)
      |> to_form(as: :reader_setting)

    {:noreply, assign(socket, :reader_settings_form, reader_settings_form)}
  end

  @impl true
  def handle_event("update_reader_settings", %{"reader_setting" => params}, socket) do
    user = socket.assigns.current_scope.user

    case Reader.update_reader_setting(user, params) do
      {:ok, reader_setting} ->
        {:noreply,
         socket
         |> assign(:reader_setting, reader_setting)
         |> assign(
           :reader_settings_form,
           reader_setting |> Reader.change_reader_setting(%{}) |> to_form(as: :reader_setting)
         )
         |> put_flash(:info, "Reader settings updated successfully.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :reader_settings_form, to_form(changeset, as: :reader_setting))}
    end
  end

  @impl true
  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params, require_current_password: true) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end

  defp timezone_options do
    zones =
      Tzdata.canonical_zone_list()
      |> Enum.reject(&(&1 in ["Etc/UTC", "Etc/GMT"]))
      |> Enum.sort()

    ["UTC" | zones]
    |> Enum.uniq()
    |> Enum.map(&{&1, &1})
  end
end
