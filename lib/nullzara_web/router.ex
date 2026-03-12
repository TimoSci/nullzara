defmodule NullzaraWeb.Router do
  use NullzaraWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {NullzaraWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug NullzaraWeb.Plugs.Auth
  end

  pipeline :require_auth do
    plug NullzaraWeb.Plugs.RequireAuth
  end

  pipeline :rate_limit_create do
    plug NullzaraWeb.Plugs.RateLimit, bucket: :create
  end

  pipeline :rate_limit_verify do
    plug NullzaraWeb.Plugs.RateLimit, bucket: :verify
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", NullzaraWeb do
    pipe_through :browser

    get "/", PageController, :home
    delete "/logout", PageController, :logout
    live "/access/token", AccessTokenLive
    live "/access/mnemonic", AccessLive
  end

  scope "/", NullzaraWeb do
    pipe_through [:browser, :rate_limit_create]

    post "/", PageController, :create
    post "/magiclink", PageController, :create_magiclink
  end

  scope "/", NullzaraWeb do
    pipe_through [:browser, :rate_limit_verify]

    get "/u/:token", TokenController, :verify
  end

  scope "/", NullzaraWeb do
    pipe_through [:browser, :require_auth]

    get "/user/:id/dashboard", DashboardController, :show
    get "/user/:id/settings", SettingsController, :show
    put "/user/:id/settings", SettingsController, :update
    post "/user/:id/settings/token", SettingsController, :regenerate_token
    delete "/user/:id/settings", SettingsController, :delete

    live_session :authenticated,
      on_mount: [{NullzaraWeb.Plugs.Auth, :require_authenticated_user}] do
      live "/users", UserLive.Index, :index
      live "/users/new", UserLive.Form, :new
      live "/users/:uuid/edit", UserLive.Form, :edit
    end
  end

  scope "/", NullzaraWeb do
    pipe_through :browser

    live_session :users_show,
      on_mount: [{NullzaraWeb.Plugs.Auth, :require_authenticated_user}] do
      live "/users/:id", UserLive.Show, :show
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:nullzara, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: NullzaraWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
