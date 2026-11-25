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

    test "a malformed signature shows an error and keeps the page alive", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/access/wallet")

      render_hook(view, "wallet_connected", %{
        "address" => "0x0000000000000000000000000000000000000000"
      })

      for signature <- ["0xzz", "0x1234", nil] do
        assert render_hook(view, "message_signed", %{"signature" => signature}) =~
                 "Signature verification failed"

        render_hook(view, "wallet_connected", %{
          "address" => "0x0000000000000000000000000000000000000000"
        })
      end

      assert Process.alive?(view.pid)
    end

    @wallets [
      %{"id" => "uuid-1", "name" => "MetaMask", "icon" => "data:image/svg+xml;base64,AAAA"},
      %{"id" => "uuid-2", "name" => "Enkrypt", "icon" => "data:image/png;base64,BBBB"}
    ]

    test "several wallets are offered as a choice", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/access/wallet")
      view |> element("#wallet-connect-btn") |> render_click()

      render_hook(view, "wallets_found", %{"wallets" => @wallets})

      assert has_element?(view, "#wallet-auth-choose-0", "MetaMask")
      assert has_element?(view, "#wallet-auth-choose-1", "Enkrypt")
      assert has_element?(view, "#wallet-auth-choose-0 img[src^='data:image/svg+xml']")
      refute render(view) =~ "Waiting for wallet"
    end

    test "choosing a wallet asks that wallet for its accounts", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/access/wallet")
      render_hook(view, "wallets_found", %{"wallets" => @wallets})

      html = view |> element("#wallet-auth-choose-1") |> render_click()

      assert_push_event(view, "request_accounts", %{wallet: "uuid-2"})
      assert html =~ "Waiting for wallet"
      refute has_element?(view, "#wallet-auth-choose-0")
    end

    test "a wallet icon that is not an image data URI is dropped", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/access/wallet")

      render_hook(view, "wallets_found", %{
        "wallets" => [
          %{"id" => "a", "name" => "Evil", "icon" => "https://example.com/track.png"},
          %{"id" => "b", "name" => "Other", "icon" => "javascript:alert(1)"}
        ]
      })

      assert has_element?(view, "#wallet-auth-choose-0", "Evil")
      refute has_element?(view, "#wallet-auth img")
    end

    test "a malformed wallet list shows an error and keeps the page alive", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/access/wallet")

      for payload <- [%{}, %{"wallets" => "nope"}, %{"wallets" => [1, %{"name" => "x"}]}] do
        assert render_hook(view, "wallets_found", payload) =~ "No wallet detected"
      end

      assert Process.alive?(view.pid)
    end
  end
end
