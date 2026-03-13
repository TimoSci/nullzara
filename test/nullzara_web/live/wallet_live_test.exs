defmodule NullzaraWeb.WalletLiveTest do
  use NullzaraWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "WalletLive" do
    test "renders the wallet login page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/access/wallet")

      assert html =~ "Wallet Login"
      assert html =~ "Sign in with Wallet"
    end

    test "connect_wallet sets loading state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/access/wallet")

      assert view
             |> element("#wallet-connect-btn")
             |> render_click() =~ "Waiting for wallet"
    end

    test "wallet_error displays the error message", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/access/wallet")

      assert render_hook(view, "wallet_error", %{"message" => "User rejected"}) =~
               "User rejected"
    end
  end
end
