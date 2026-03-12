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
end
