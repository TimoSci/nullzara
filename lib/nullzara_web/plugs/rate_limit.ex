defmodule NullzaraWeb.Plugs.RateLimit do
  @moduledoc """
  Plug that blocks IPs exceeding the failure threshold.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2, put_flash: 3]

  alias Nullzara.RateLimiter

  def init(opts), do: opts

  def call(conn, _opts) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()

    if RateLimiter.blocked?(ip) do
      conn
      |> put_flash(:error, "Too many failed attempts. Please try again later.")
      |> redirect(to: "/access/token")
      |> halt()
    else
      conn
    end
  end
end
