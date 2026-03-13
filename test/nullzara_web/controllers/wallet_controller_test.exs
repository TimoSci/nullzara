defmodule NullzaraWeb.WalletControllerTest do
  use NullzaraWeb.ConnCase, async: true

  alias Nullzara.Users

  describe "complete/2" do
    test "logs in user with valid token", %{conn: conn} do
      {:ok, user} = Users.create_user_with_token(%{name: "Test"})
      token = Phoenix.Token.sign(NullzaraWeb.Endpoint, "wallet_auth", user.id)

      conn = get(conn, ~p"/access/wallet/complete?token=#{token}")

      assert redirected_to(conn) =~ "/user/"
      assert get_session(conn, :user_id) == user.id
    end

    test "rejects invalid token", %{conn: conn} do
      conn = get(conn, ~p"/access/wallet/complete?token=invalid_token")

      assert redirected_to(conn) == "/access/wallet"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "expired"
    end
  end
end
