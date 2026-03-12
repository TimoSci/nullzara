defmodule NullzaraWeb.PageControllerTest do
  use NullzaraWeb.ConnCase

  test "GET / renders the home page with dashboard and create button", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    assert html =~ "App Dashboard"
    assert html =~ "Create Anonymous Account"
  end

  test "POST / creates an anonymous user and redirects to /u/:token", %{conn: conn} do
    conn = post(conn, ~p"/")
    assert "/u/" <> _token = redirected_to(conn)
  end

  test "POST / shows welcome page with mnemonic and bookmark button", %{conn: conn} do
    conn = post(conn, ~p"/")
    redirect_path = redirected_to(conn)

    conn = get(recycle(conn), redirect_path)
    html = html_response(conn, 200)
    assert html =~ "Save Your Recovery Phrase"
    assert html =~ "Done!"
  end
end
