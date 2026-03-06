defmodule IcarurssWeb.Router do
  use IcarurssWeb, :router

  import IcarurssWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {IcarurssWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Other scopes may use custom stacks.
  # scope "/api", IcarurssWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:icarurss, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: IcarurssWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", IcarurssWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{IcarurssWeb.UserAuth, :require_authenticated}] do
      live "/", ReaderLive, :index
      live "/users/settings", UserLive.Settings, :reader
      live "/users/settings/reader", UserLive.Settings, :reader
      live "/users/settings/opml", UserLive.Settings, :opml
      live "/users/settings/feeds", UserLive.Settings, :opml
      live "/users/settings/username", UserLive.Settings, :username
      live "/users/settings/password", UserLive.Settings, :password
    end

    get "/users/settings/opml/export", FeedSettingsController, :export_opml
    post "/users/settings/opml/import", FeedSettingsController, :import_opml
    post "/users/settings/opml/reset", FeedSettingsController, :reset_opml_data
    get "/users/settings/feeds/export", FeedSettingsController, :export_opml
    post "/users/settings/feeds/import", FeedSettingsController, :import_opml
    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", IcarurssWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{IcarurssWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
