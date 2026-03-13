defmodule NullzaraWeb.Plugs.Auth do
  @moduledoc """
  Plug that reads user_id from session and assigns current_user.
  Also provides on_mount callbacks for LiveView authentication.
  """

  import Plug.Conn
  import Phoenix.Component, only: [assign_new: 3]

  alias Nullzara.Users
  alias Nullzara.Users.User

  def init(opts), do: opts

  def call(conn, _opts) do
    user_id = get_session(conn, :user_id)
    user = user_id && Users.get_user(user_id)
    user = user && Nullzara.Repo.preload(user, :wallet_credential)
    user = maybe_attach_login_token(user, get_session(conn, :login_token))
    assign(conn, :current_user, user)
  end

  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, mount_current_user(socket, session)}
  end

  def on_mount(:require_authenticated_user, params, session, socket) do
    socket = mount_current_user(socket, session)

    cond do
      socket.assigns.current_user ->
        {:cont, socket}

      # Allow magiclink users to authenticate via login token in URL
      is_binary(params["id"]) ->
        case Users.get_user_by_login_token(params["id"]) do
          {:ok, user} ->
            if User.is_magiclink?(user) do
              user = %{user | raw_login_token: params["id"]}
              {:cont, Phoenix.Component.assign(socket, :current_user, user)}
            else
              {:halt, Phoenix.LiveView.redirect(socket, to: "/access/token")}
            end

          _ ->
            {:halt, Phoenix.LiveView.redirect(socket, to: "/access/token")}
        end

      true ->
        {:halt, Phoenix.LiveView.redirect(socket, to: "/access/token")}
    end
  end

  defp mount_current_user(socket, session) do
    assign_new(socket, :current_user, fn ->
      user_id = session["user_id"]
      user = user_id && Users.get_user(user_id)
      user = user && Nullzara.Repo.preload(user, :wallet_credential)
      maybe_attach_login_token(user, session["login_token"])
    end)
  end

  defp maybe_attach_login_token(%User{mnemonic_hash: nil} = user, token) when is_binary(token) do
    %{user | raw_login_token: token}
  end

  defp maybe_attach_login_token(user, _token), do: user
end
