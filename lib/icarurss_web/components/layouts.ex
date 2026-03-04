defmodule IcarurssWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use IcarurssWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :full_width, :boolean,
    default: false,
    doc: "whether to render the inner content in a full-bleed layout"

  slot :header_content,
    doc: "optional page-specific content rendered inside the main app header"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="flex min-h-screen flex-col">
      <header class="w-full border-b border-base-300 bg-base-100/80 px-4 py-3 backdrop-blur sm:px-6 lg:px-8">
        <div class="flex w-full items-center justify-between gap-3">
          <a href="/" class="flex w-fit items-center gap-2">
            <img src={~p"/images/logo.svg"} width="36" />
            <span class="text-sm font-semibold">v{Application.spec(:phoenix, :vsn)}</span>
          </a>

          <nav class="flex items-center gap-2 sm:gap-3">
            <a href="https://phoenixframework.org/" class="btn btn-ghost btn-sm hidden lg:inline-flex">
              Website
            </a>
            <a
              href="https://github.com/phoenixframework/phoenix"
              class="btn btn-ghost btn-sm hidden lg:inline-flex"
            >
              GitHub
            </a>
            <.theme_toggle />

            <%= if @current_scope && @current_scope.user do %>
              <span class="hidden md:inline text-sm text-base-content/80">
                {@current_scope.user.username || @current_scope.user.email}
              </span>
              <.link href={~p"/users/settings/reader"} class="btn btn-ghost btn-sm">Settings</.link>
              <.link href={~p"/users/log-out"} method="delete" class="btn btn-ghost btn-sm">
                Log out
              </.link>
            <% else %>
              <.link
                :if={Icarurss.Accounts.registration_enabled?()}
                href={~p"/users/register"}
                class="btn btn-ghost btn-sm"
              >
                Register
              </.link>
              <.link href={~p"/users/log-in"} class="btn btn-primary btn-sm">Log in</.link>
            <% end %>
          </nav>
        </div>

        <div :if={@header_content != []} class="mt-3 border-t border-base-300 pt-3">
          {render_slot(@header_content)}
        </div>
      </header>

      <main class={[
        "w-full flex-1 min-h-0",
        @full_width && "py-0",
        !@full_width && "px-4 py-6 sm:px-6 lg:px-8"
      ]}>
        <div class={[
          "w-full h-full",
          !@full_width && "mx-auto max-w-7xl space-y-4"
        ]}>
          {render_slot(@inner_block)}
        </div>
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
