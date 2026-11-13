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

    test "shows the signed-in navbar to a signed-in user", %{conn: conn} do
      {user, _mnemonic_token, _login_token} = user_fixture_with_token()
      {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/access/token")

      assert has_element?(view, ~s|header form[action="/logout"]|)
      refute has_element?(view, ~s|header a[href="/access/passkey"]|)
    end

    test "shows the logged-out navbar to a visitor", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/access/token")

      refute has_element?(view, ~s|header form[action="/logout"]|)
      assert has_element?(view, ~s|header a[href="/access/passkey"]|)
    end

    test "redirects to /u/:token on valid hex token", %{conn: conn} do
      {_user, _raw_mnemonic_token, raw_token} = user_fixture_with_token()

      {:ok, live_view, _html} = live(conn, ~p"/access/token")

      result =
        live_view
        |> form("#token-form", access: %{token: raw_token})
        |> render_submit()

      assert {:error, {:redirect, %{to: to}}} = result
      assert to == "/u/" <> raw_token
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
