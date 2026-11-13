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

  describe "PUT /user/:id/settings with a too-long nickname" do
    test "re-renders the form with an error", %{conn: conn, user: user} do
      conn =
        conn
        |> log_in_user(user)
        |> put(~p"/user/#{user}/settings", %{"user" => %{"name" => String.duplicate("a", 300)}})

      assert html_response(conn, 200) =~ "should be at most 50 character(s)"
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

  describe "POST /user/:id/settings/token as a magic-link user" do
    setup %{conn: conn} do
      {:ok, user} = Nullzara.Users.create_magiclink_user(%{name: "magic"})
      token = user.raw_login_token
      conn = conn |> get(~p"/u/#{token}") |> recycle()
      %{conn: conn, old_token: token, magic_user: user}
    end

    test "the session follows the new token", %{conn: conn, old_token: old_token} do
      conn = post(conn, ~p"/user/#{old_token}/settings/token")
      new_token = get_session(conn, :login_token)

      assert new_token != old_token
      assert Phoenix.Flash.get(conn.assigns.flash, :new_login_token) == new_token
      assert redirected_to(conn) == ~p"/user/#{new_token}/settings"
    end

    test "regenerating twice keeps the user signed in with working links",
         %{conn: conn, old_token: old_token, magic_user: user} do
      conn = post(conn, ~p"/user/#{old_token}/settings/token")
      new_token = get_session(conn, :login_token)

      conn = post(recycle(conn), ~p"/user/#{new_token}/settings/token")
      newest = get_session(conn, :login_token)
      refute newest in [old_token, new_token]

      conn = get(recycle(conn), ~p"/user/#{newest}/settings")
      html = html_response(conn, 200)
      assert html =~ ~s|href="/user/#{newest}/settings"|
      refute html =~ old_token
      refute html =~ new_token
      assert get_session(conn, :user_id) == user.id
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
