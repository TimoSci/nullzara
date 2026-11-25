defmodule NullzaraWeb.WalletSettingsLiveTest do
  use NullzaraWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Nullzara.Users

  setup %{conn: conn} do
    {:ok, user} = Users.create_user_with_token(%{name: "Test"})
    conn = conn |> init_test_session(%{user_id: user.id})
    %{conn: conn, user: user}
  end

  describe "WalletSettingsLive" do
    test "renders the connect wallet page", %{conn: conn, user: user} do
      {:ok, _view, html} = live(conn, ~p"/user/#{user}/settings/wallet")

      assert html =~ "Connect Wallet"
      assert html =~ "Back to Settings"
    end

    test "connect_wallet sets loading state", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/user/#{user}/settings/wallet")

      assert view
             |> element("#wallet-attach-btn")
             |> render_click() =~ "Waiting for wallet"
    end

    test "wallet_error displays the error message", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/user/#{user}/settings/wallet")

      assert render_hook(view, "wallet_error", %{"message" => "No wallet detected"}) =~
               "No wallet detected"
    end

    test "a malformed signature shows an error and keeps the page alive", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/user/#{user}/settings/wallet")

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

    test "several wallets are offered and the chosen one is used", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/user/#{user}/settings/wallet")

      render_hook(view, "wallets_found", %{
        "wallets" => [
          %{"id" => "uuid-1", "name" => "MetaMask", "icon" => nil},
          %{"id" => "uuid-2", "name" => "Enkrypt", "icon" => nil}
        ]
      })

      assert has_element?(view, "#wallet-settings-choose-0", "MetaMask")

      view |> element("#wallet-settings-choose-1") |> render_click()

      assert_push_event(view, "request_accounts", %{wallet: "uuid-2"})
    end
  end
end
