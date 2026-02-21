defmodule UserphoenixWeb.Router do
  use UserphoenixWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {UserphoenixWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug UserphoenixWeb.Plugs.Auth
  end

  pipeline :require_auth do
    plug UserphoenixWeb.Plugs.RequireAuth
  end

  pipeline :rate_limited do
    plug UserphoenixWeb.Plugs.RateLimit
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", UserphoenixWeb do
    pipe_through :browser

    get "/", PageController, :home
    delete "/logout", PageController, :logout
    live "/access/token", AccessTokenLive
    live "/access/mnemonic", AccessLive
  end

  scope "/", UserphoenixWeb do
    pipe_through [:browser, :rate_limited]

    post "/", PageController, :create
    get "/u/:token", TokenController, :verify
  end

  scope "/", UserphoenixWeb do
    pipe_through [:browser, :require_auth]

    get "/user/:uuid/dashboard", DashboardController, :show
    get "/user/:uuid/settings", SettingsController, :show
    put "/user/:uuid/settings", SettingsController, :update
    post "/user/:uuid/settings/token", SettingsController, :regenerate_token
    delete "/user/:uuid/settings", SettingsController, :delete

    live_session :authenticated,
      on_mount: [{UserphoenixWeb.Plugs.Auth, :require_authenticated_user}] do
      live "/users", UserLive.Index, :index
      live "/users/new", UserLive.Form, :new
      live "/users/:uuid", UserLive.Show, :show
      live "/users/:uuid/edit", UserLive.Form, :edit
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:userphoenix, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: UserphoenixWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
