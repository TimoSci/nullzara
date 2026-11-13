defmodule Nullzara.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    normalize_admin_uuids()

    children = [
      NullzaraWeb.Telemetry,
      Nullzara.Repo,
      {DNSCluster, query: Application.get_env(:nullzara, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Nullzara.PubSub},
      Nullzara.RateLimiter,
      # Start to serve requests, typically the last entry
      NullzaraWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Nullzara.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # ADMIN_UUIDS arrives from config/runtime.exs as the raw comma-separated
  # string. Parse it once at boot so an invalid entry stops the app here.
  defp normalize_admin_uuids do
    case Application.get_env(:nullzara, :admin_uuids) do
      value when is_binary(value) ->
        Application.put_env(:nullzara, :admin_uuids, Nullzara.Users.parse_admin_uuids(value))

      _ ->
        :ok
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    NullzaraWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
