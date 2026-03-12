defmodule NullzaraWeb.Plugs.Auth do
  @moduledoc """
  Plug that reads user_id from session and assigns current_user.
  Also provides on_mount callbacks for LiveView authentication.
  """

  import Plug.Conn
  import Phoenix.Component, only: [assign_new: 3]

  alias Nullzara.Users

  def init(opts), do: opts

  def call(conn, _opts) do
    user_id = get_session(conn, :user_id)
    user = user_id && Users.get_user(user_id)
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
          {:ok, %{mnemonic_hash: nil} = user} ->
            {:cont, Phoenix.Component.assign(socket, :current_user, user)}

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
      user_id && Users.get_user(user_id)
    end)
  end
end
