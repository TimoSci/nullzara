defmodule NullzaraWeb.TokenControllerTest do
  use NullzaraWeb.ConnCase

  import Nullzara.UsersFixtures

  describe "GET /u/:token with login token" do
    test "redirects to dashboard with valid login token", %{conn: conn} do
      {user, _mnemonic_token, login_token} = user_fixture_with_token()

      conn = get(conn, ~p"/u/#{login_token}")
      assert redirected_to(conn) == ~p"/user/#{user}/dashboard"
    end

    test "does not store mnemonic_token in session when logging in via login token", %{
      conn: conn
    } do
      {user, _mnemonic_token, login_token} = user_fixture_with_token()

      conn = get(conn, ~p"/u/#{login_token}")
      conn = get(recycle(conn), ~p"/user/#{user}/settings")
      refute get_session(conn, :mnemonic_token)
    end

    test "sets session on valid login token", %{conn: conn} do
      {user, _mnemonic_token, login_token} = user_fixture_with_token()

      conn = get(conn, ~p"/u/#{login_token}")
      conn = get(recycle(conn), ~p"/user/#{user}/dashboard")
      assert conn.status == 200
    end
  end

  describe "GET /u/:token with mnemonic token" do
    test "redirects to dashboard with valid mnemonic token", %{conn: conn} do
      {user, mnemonic_token, _login_token} = user_fixture_with_token()

      conn = get(conn, ~p"/u/#{mnemonic_token}")
      assert redirected_to(conn) == ~p"/user/#{user}/dashboard"
    end

    test "stores mnemonic_token in session when logging in via mnemonic", %{conn: conn} do
      {user, mnemonic_token, _login_token} = user_fixture_with_token()

      conn = get(conn, ~p"/u/#{mnemonic_token}")
      conn = get(recycle(conn), ~p"/user/#{user}/settings")
      assert get_session(conn, :mnemonic_token) == mnemonic_token
    end

    test "renders welcome page when mnemonic flash is present", %{conn: conn} do
      {_user, mnemonic_token, _login_token} = user_fixture_with_token()

      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{})
        |> fetch_flash()
        |> put_flash(:mnemonic, "test mnemonic phrase")
        |> get(~p"/u/#{mnemonic_token}")

      html = html_response(conn, 200)
      assert html =~ "Save Your Recovery Phrase"
      assert html =~ "Done!"
      assert html =~ "test mnemonic phrase"
    end
  end

  describe "GET /u/:token with invalid token" do
    test "redirects to /access/token with invalid token", %{conn: conn} do
      conn = get(conn, ~p"/u/invalidtoken1234567890abcdef00")
      assert redirected_to(conn) == ~p"/access/token"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid access token"
    end
  end
end
