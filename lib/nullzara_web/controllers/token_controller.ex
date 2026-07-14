defmodule NullzaraWeb.TokenController do
  use NullzaraWeb, :controller

  alias Nullzara.Users
  alias Nullzara.Users.Mnemonic
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

        show_welcome = get_session(conn, :show_welcome)

        cond do
          show_welcome == "mnemonic" and match_type == :mnemonic ->
            render(conn, :welcome,
              user: user,
              mnemonic: Mnemonic.encode(raw_token),
              login_token: get_session(conn, :login_token)
            )

          show_welcome == "magiclink" and Users.User.is_magiclink?(user) ->
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

  def acknowledge(conn, _params) do
    user = conn.assigns.current_user

    conn = delete_session(conn, :show_welcome)

    # Magiclink users need the raw login token in session for URL generation;
    # for mnemonic users it was only kept for the welcome page.
    conn =
      if Users.User.is_magiclink?(user),
        do: conn,
        else: delete_session(conn, :login_token)

    redirect(conn, to: ~p"/user/#{user}/dashboard")
  end
end
