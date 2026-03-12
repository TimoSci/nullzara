defmodule NullzaraWeb.Plugs.RateLimit do
  @moduledoc """
  Plug that blocks IPs exceeding the failure threshold for a given bucket.

  Usage in router:

      plug NullzaraWeb.Plugs.RateLimit, bucket: :verify
  """

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2, put_flash: 3]

  alias Nullzara.RateLimiter

  def init(opts), do: opts

  def call(conn, opts) do
    bucket = Keyword.get(opts, :bucket, :default)
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()

    if RateLimiter.blocked?(bucket, ip) do
      conn
      |> put_flash(:error, "Too many attempts. Please try again later.")
      |> redirect(to: "/")
      |> halt()
    else
      conn
    end
  end
end
