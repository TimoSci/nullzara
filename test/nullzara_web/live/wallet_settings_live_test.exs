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
  end
end
