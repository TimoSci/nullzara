defmodule NullzaraWeb.AccessTokenLiveTest do
  use NullzaraWeb.ConnCase

  import Phoenix.LiveViewTest
  import Nullzara.UsersFixtures

  describe "Access token page" do
    test "renders the token form", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/access/token")

      assert html =~ "Access Your Account"
      assert html =~ "Access Token"
    end

    test "redirects to /u/:token on valid hex token", %{conn: conn} do
      {_user, _raw_mnemonic_token, raw_token} = user_fixture_with_token()

      {:ok, live_view, _html} = live(conn, ~p"/access/token")

      result =
        live_view
        |> form("#token-form", access: %{token: raw_token})
        |> render_submit()

      assert {:error, {:live_redirect, %{to: "/u/" <> _token}}} = result
    end

    test "shows error for invalid token format", %{conn: conn} do
      {:ok, live_view, _html} = live(conn, ~p"/access/token")

      live_view
      |> form("#token-form", access: %{token: "not-a-valid-token"})
      |> render_submit()

      html = render(live_view)
      assert html =~ "Invalid token format"
    end

    test "has link to mnemonic login page", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/access/token")
      assert html =~ "Login with recovery phrase instead"
    end
  end
end
