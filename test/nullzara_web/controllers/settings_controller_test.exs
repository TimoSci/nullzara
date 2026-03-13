defmodule NullzaraWeb.SettingsControllerTest do
  use NullzaraWeb.ConnCase

  import Nullzara.UsersFixtures

  setup do
    {user, mnemonic_token, login_token} = user_fixture_with_token()
    %{user: user, mnemonic_token: mnemonic_token, login_token: login_token}
  end

  describe "GET /user/:id/settings" do
    test "renders settings for authenticated user", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> get(~p"/user/#{user}/settings")
      assert html_response(conn, 200) =~ "Settings"
      assert html_response(conn, 200) =~ "Nickname"
    end

    test "shows mnemonic when logged in via mnemonic", %{
      conn: conn,
      user: user,
      mnemonic_token: mnemonic_token
    } do
      conn =
        conn
        |> log_in_user(user)
        |> put_session(:mnemonic_token, mnemonic_token)
        |> get(~p"/user/#{user}/settings")

      assert html_response(conn, 200) =~ "Recovery Phrase"
    end

    test "hides mnemonic when logged in via login token", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> get(~p"/user/#{user}/settings")
      refute html_response(conn, 200) =~ "Recovery Phrase"
    end

    test "redirects to /access when not authenticated", %{conn: conn, user: user} do
      conn = get(conn, ~p"/user/#{user}/settings")
      assert redirected_to(conn) == "/access/token"
    end
  end

  describe "PUT /user/:id/settings" do
    test "updates the user name", %{conn: conn, user: user} do
      conn =
        conn
        |> log_in_user(user)
        |> put(~p"/user/#{user}/settings", %{"user" => %{"name" => "New Name"}})

      assert redirected_to(conn) == ~p"/user/#{user}/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Settings updated"
    end

    test "re-renders on invalid data", %{conn: conn, user: user} do
      conn =
        conn
        |> log_in_user(user)
        |> put(~p"/user/#{user}/settings", %{"user" => %{"name" => ""}})

      assert html_response(conn, 200) =~ "Settings"
    end
  end

  describe "POST /user/:id/settings/token" do
    test "regenerates login token and shows new token", %{conn: conn, user: user} do
      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/user/#{user}/settings/token")

      assert redirected_to(conn) == ~p"/user/#{user}/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :new_login_token)
    end

    test "old login token stops working after regeneration", %{
      conn: conn,
      user: user,
      login_token: old_login_token
    } do
      conn
      |> log_in_user(user)
      |> post(~p"/user/#{user}/settings/token")

      conn = build_conn() |> get(~p"/u/#{old_login_token}")
      assert redirected_to(conn) == ~p"/access/token"
    end

    test "mnemonic token still works after login token regeneration", %{
      conn: conn,
      user: user,
      mnemonic_token: mnemonic_token
    } do
      conn
      |> log_in_user(user)
      |> post(~p"/user/#{user}/settings/token")

      conn = build_conn() |> get(~p"/u/#{mnemonic_token}")
      assert redirected_to(conn) == ~p"/user/#{user}/dashboard"
    end
  end

  describe "DELETE /user/:id/settings" do
    test "deletes the account and redirects to home", %{conn: conn, user: user} do
      conn =
        conn
        |> log_in_user(user)
        |> delete(~p"/user/#{user}/settings")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Account deleted"
    end
  end
end
