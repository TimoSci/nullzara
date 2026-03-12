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

        {conn, user} =
          cond do
            match_type == :mnemonic ->
              {put_session(conn, :mnemonic_token, raw_token), user}

            Users.User.is_magiclink?(user) ->
              {put_session(conn, :login_token, raw_token), %{user | raw_login_token: raw_token}}

            true ->
              {conn, user}
          end

        cond do
          Phoenix.Flash.get(conn.assigns.flash, :mnemonic) ->
            render(conn, :welcome, user: user, token: raw_token)

          Phoenix.Flash.get(conn.assigns.flash, :magiclink) ->
            render(conn, :magiclink_welcome, user: user, token: raw_token)

          true ->
            redirect(conn, to: ~p"/user/#{user}/dashboard")
        end

      {:error, :not_found} ->
        ip = conn.remote_ip |> :inet.ntoa() |> to_string()
        RateLimiter.record(:verify, ip)

        conn
        |> put_flash(:error, "Invalid access token.")
        |> redirect(to: ~p"/access/token")
    end
  end
end
