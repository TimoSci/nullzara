defmodule NullzaraWeb.PasskeyController do
  use NullzaraWeb, :controller

  alias Nullzara.Users

  def complete(conn, %{"token" => token}) do
    case Phoenix.Token.verify(NullzaraWeb.Endpoint, "passkey_auth", token, max_age: 60) do
      {:ok, user_id} ->
        user = Users.get_user!(user_id)

        conn
        |> put_session(:user_id, user.id)
        |> configure_session(renew: true)
        |> redirect(to: ~p"/user/#{user}/dashboard")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Passkey session expired. Please try again.")
        |> redirect(to: ~p"/access/passkey")
    end
  end
end
