defmodule NullzaraWeb.DashboardControllerTest do
  use NullzaraWeb.ConnCase

  import Nullzara.UsersFixtures

  setup do
    {user, _mnemonic_token, _login_token} = user_fixture_with_token()
    %{user: user}
  end

  test "GET /user/:id/dashboard renders the dashboard for authenticated user", %{
    conn: conn,
    user: user
  } do
    conn = conn |> log_in_user(user) |> get(~p"/user/#{user}/dashboard")
    assert html_response(conn, 200) =~ "Dashboard"
    assert html_response(conn, 200) =~ user.name
  end

  test "GET /user/:id/dashboard redirects to /access when not authenticated", %{
    conn: conn,
    user: user
  } do
    conn = get(conn, ~p"/user/#{user}/dashboard")
    assert redirected_to(conn) == "/access/token"
  end

  describe "an address for a different account" do
    test "GET with a made-up id redirects to the signed-in user's dashboard",
         %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> get(~p"/user/not-me/dashboard")
      assert redirected_to(conn) == ~p"/user/#{user}/dashboard"
    end

    test "GET with another user's UUID redirects to the signed-in user's dashboard",
         %{conn: conn, user: user} do
      {other, _mnemonic_token, _login_token} = user_fixture_with_token()

      for path <- [~p"/user/#{other}/dashboard", ~p"/user/#{other}/settings"] do
        conn = conn |> log_in_user(user) |> get(path)
        assert redirected_to(conn) == ~p"/user/#{user}/dashboard"
      end
    end

    test "writes to another id are refused and change nothing", %{conn: conn, user: user} do
      {other, _mnemonic_token, _login_token} = user_fixture_with_token()
      conn = log_in_user(conn, user)

      conn = put(conn, ~p"/user/#{other}/settings", %{"user" => %{"name" => "changed"}})
      assert redirected_to(conn) == ~p"/user/#{user}/dashboard"

      conn = conn |> recycle() |> log_in_user(user) |> delete(~p"/user/#{other}/settings")
      assert redirected_to(conn) == ~p"/user/#{user}/dashboard"

      assert Nullzara.Users.get_user!(user.id).name == "some name"
      assert Nullzara.Users.get_user!(other.id).name == "some name"
    end

    test "a magic-link user is accepted under their token and under their UUID", %{conn: conn} do
      {:ok, magic} = Nullzara.Users.create_magiclink_user(%{name: "magic"})
      conn = conn |> get(~p"/u/#{magic.raw_login_token}") |> recycle()

      assert conn |> get(~p"/user/#{magic.raw_login_token}/dashboard") |> html_response(200)
      assert conn |> get("/user/#{magic.uuid}/dashboard") |> html_response(200)
    end
  end
end
