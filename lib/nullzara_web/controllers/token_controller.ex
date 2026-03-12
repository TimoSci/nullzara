defmodule NullzaraWeb.TokenController do
  use NullzaraWeb, :controller

  alias Nullzara.Users
  alias Nullzara.RateLimiter

  def verify(conn, %{"token" => raw_token}) do
    case Users.get_user_by_token(raw_token) do
      {:ok, user, match_type} ->
        conn =
          conn
          |> put_session(:user_id, user.id)
          |> configure_session(renew: true)

        conn =
          if match_type == :mnemonic do
            put_session(conn, :mnemonic_token, raw_token)
          else
            conn
          end

        if Phoenix.Flash.get(conn.assigns.flash, :mnemonic) do
          render(conn, :welcome, user: user, token: raw_token)
        else
          redirect(conn, to: ~p"/user/#{user}/dashboard")
        end

      {:error, :not_found} ->
        ip = conn.remote_ip |> :inet.ntoa() |> to_string()
        RateLimiter.record_failure(ip)

        conn
        |> put_flash(:error, "Invalid access token.")
        |> redirect(to: ~p"/access/token")
    end
  end
end
