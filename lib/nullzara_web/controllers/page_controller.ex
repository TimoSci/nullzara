defmodule NullzaraWeb.PageController do
  use NullzaraWeb, :controller

  alias Nullzara.Users
  alias Nullzara.Users.Mnemonic
  alias Nullzara.RateLimiter

  def home(conn, _params) do
    render(conn, :home)
  end

  def logout(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: ~p"/")
  end

  def create(conn, _params) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    RateLimiter.record(:create, ip)

    case Users.create_user_with_token(%{name: "Anonymous"}) do
      {:ok, user} ->
        mnemonic = Mnemonic.encode(user.raw_token)

        conn
        |> put_flash(:mnemonic, mnemonic)
        |> put_flash(:login_token, user.raw_login_token)
        |> redirect(to: ~p"/u/#{user.raw_token}")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Could not create account.")
        |> redirect(to: ~p"/")
    end
  end

  def create_magiclink(conn, _params) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    RateLimiter.record(:create, ip)

    case Users.create_magiclink_user(%{name: "Anonymous"}) do
      {:ok, user} ->
        conn
        |> put_flash(:magiclink, user.raw_login_token)
        |> redirect(to: ~p"/u/#{user.raw_login_token}")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Could not create account.")
        |> redirect(to: ~p"/")
    end
  end
end
