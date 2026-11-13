defmodule NullzaraWeb.Plugs.RequireAuth do
  @moduledoc """
  Plug that redirects unauthenticated users to /access/token.

  On routes with an `:id` segment (`/user/:id/...`), the id must also name
  the signed-in account: its URL id (`Phoenix.Param`) or its UUID. Any
  other id is redirected to the signed-in user's own dashboard.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    user = conn.assigns[:current_user]

    cond do
      is_nil(user) ->
        conn
        |> redirect(to: "/access/token")
        |> halt()

      own_id?(user, conn.path_params["id"]) ->
        conn

      true ->
        conn
        |> redirect(to: "/user/#{Phoenix.Param.to_param(user)}/dashboard")
        |> halt()
    end
  end

  defp own_id?(_user, nil), do: true

  defp own_id?(user, id) when is_binary(id) do
    id == Phoenix.Param.to_param(user) or String.downcase(id) == user.uuid
  end
end
