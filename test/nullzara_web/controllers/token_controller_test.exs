defmodule NullzaraWeb.TokenControllerTest do
  use NullzaraWeb.ConnCase

  import Nullzara.UsersFixtures

  alias Nullzara.Users
  alias Nullzara.Users.Mnemonic

  defp clear_rate_limits(_context) do
    ip = Phoenix.ConnTest.build_conn().remote_ip |> :inet.ntoa() |> to_string()
    Nullzara.RateLimiter.clear(:create, ip)
    Nullzara.RateLimiter.clear(:verify, ip)
    on_exit(fn -> Nullzara.RateLimiter.clear(:create, ip) end)
    :ok
  end

  # The login token is the only 32-char hex string rendered on the welcome
  # page (the mnemonic token appears only in the URL, never in the body).
  defp extract_login_token(html, raw_token) do
    ~r/\b[a-f0-9]{32}\b/
    |> Regex.scan(html)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.reject(&(&1 == raw_token))
    |> case do
      [login_token] -> login_token
      other -> flunk("expected exactly one login token in welcome page, got: #{inspect(other)}")
    end
  end

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

  describe "GET /u/:token in upper case" do
    test "accepts the login token in upper case", %{conn: conn} do
      {user, _token, login_token} = user_fixture_with_token()
      conn = get(conn, ~p"/u/#{String.upcase(login_token)}")
      assert redirected_to(conn) == ~p"/user/#{user}/dashboard"
    end

    test "stores the mnemonic token in lower case", %{conn: conn} do
      {_user, raw_token, _login_token} = user_fixture_with_token()
      conn = get(conn, ~p"/u/#{String.upcase(raw_token)}")
      assert get_session(conn, :mnemonic_token) == raw_token
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
  end

  describe "welcome flow after anonymous signup" do
    setup :clear_rate_limits

    test "shows welcome page with mnemonic and working login token", %{conn: conn} do
      conn = post(conn, ~p"/")
      assert "/u/" <> raw_token = path = redirected_to(conn)

      conn = get(recycle(conn), path)
      html = html_response(conn, 200)
      assert html =~ "Save Your Recovery Phrase"
      assert html =~ Mnemonic.encode(raw_token)

      login_token = extract_login_token(html, raw_token)
      conn2 = get(build_conn(), ~p"/u/#{login_token}")
      assert redirected_to(conn2) =~ "/dashboard"
    end

    test "welcome page survives a refresh", %{conn: conn} do
      conn = post(conn, ~p"/")
      assert "/u/" <> raw_token = path = redirected_to(conn)

      conn = get(recycle(conn), path)
      first_html = html_response(conn, 200)
      assert first_html =~ "Save Your Recovery Phrase"
      login_token = extract_login_token(first_html, raw_token)

      conn = get(recycle(conn), path)
      html = html_response(conn, 200)
      assert html =~ "Save Your Recovery Phrase"
      assert html =~ Mnemonic.encode(raw_token)
      assert extract_login_token(html, raw_token) == login_token
    end

    test "does not store credentials in flash", %{conn: conn} do
      conn = post(conn, ~p"/")
      refute Phoenix.Flash.get(conn.assigns.flash, :mnemonic)
      refute Phoenix.Flash.get(conn.assigns.flash, :login_token)
    end

    test "Done acknowledges the welcome page and stops showing it", %{conn: conn} do
      conn = post(conn, ~p"/")
      assert "/u/" <> raw_token = path = redirected_to(conn)

      conn = get(recycle(conn), path)
      assert html_response(conn, 200) =~ "Save Your Recovery Phrase"

      {:ok, user, :mnemonic} = Users.get_user_by_token(raw_token)
      conn = post(recycle(conn), ~p"/user/#{user}/welcome/done")
      assert redirected_to(conn) == ~p"/user/#{user}/dashboard"

      conn = get(recycle(conn), path)
      assert redirected_to(conn) == ~p"/user/#{user}/dashboard"
    end
  end

  describe "welcome flow after magiclink signup" do
    setup :clear_rate_limits

    test "shows magic link welcome page and survives a refresh", %{conn: conn} do
      conn = post(conn, ~p"/magiclink")
      assert "/u/" <> token = path = redirected_to(conn)

      conn = get(recycle(conn), path)
      html = html_response(conn, 200)
      assert html =~ "Save Your Magic Link"
      assert html =~ token

      conn = get(recycle(conn), path)
      html = html_response(conn, 200)
      assert html =~ "Save Your Magic Link"
      assert html =~ token
    end

    test "the magic link shown on the welcome page is the login link", %{conn: conn} do
      conn = post(conn, ~p"/magiclink")
      assert "/u/" <> token = path = redirected_to(conn)

      html = conn |> recycle() |> get(path) |> html_response(200)

      assert html =~ "#{NullzaraWeb.Endpoint.url()}/u/#{token}"
      refute html =~ "/users/#{token}"
    end

    test "Done acknowledges the welcome page and login keeps working", %{conn: conn} do
      conn = post(conn, ~p"/magiclink")
      assert "/u/" <> token = path = redirected_to(conn)

      conn = get(recycle(conn), path)
      assert html_response(conn, 200) =~ "Save Your Magic Link"

      {:ok, user, :token} = Users.get_user_by_token(token)
      # Magiclink users are addressed by their raw login token in URLs
      user = %{user | raw_login_token: token}
      conn = post(recycle(conn), ~p"/user/#{user}/welcome/done")
      assert redirected_to(conn) == ~p"/user/#{user}/dashboard"

      conn = get(recycle(conn), path)
      assert redirected_to(conn) == ~p"/user/#{user}/dashboard"
    end
  end

  describe "GET /u/:token with invalid token" do
    test "an unknown recovery phrase goes back to the phrase page", %{conn: conn} do
      conn = get(conn, ~p"/u/00000000000000000000000000000000?via=mnemonic")
      assert redirected_to(conn) == ~p"/access/mnemonic"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "No account matches that recovery phrase."
    end

    test "a failed recovery phrase still counts against the rate limit", %{conn: conn} do
      ip = conn.remote_ip |> :inet.ntoa() |> to_string()
      Nullzara.RateLimiter.clear(:verify, ip)
      on_exit(fn -> Nullzara.RateLimiter.clear(:verify, ip) end)
      {limit, _window} = Application.get_env(:nullzara, Nullzara.RateLimiter)[:limits][:verify]

      for _ <- 1..limit do
        get(build_conn(), ~p"/u/00000000000000000000000000000000?via=mnemonic")
      end

      conn = get(build_conn(), ~p"/u/00000000000000000000000000000000?via=mnemonic")
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Too many attempts"
    end

    test "redirects to /access/token with invalid token", %{conn: conn} do
      conn = get(conn, ~p"/u/invalidtoken1234567890abcdef00")
      assert redirected_to(conn) == ~p"/access/token"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid access token"
    end
  end
end
