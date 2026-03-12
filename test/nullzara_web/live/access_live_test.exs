defmodule NullzaraWeb.AccessLiveTest do
  use NullzaraWeb.ConnCase

  import Phoenix.LiveViewTest
  import Nullzara.UsersFixtures

  alias Nullzara.Users.Mnemonic

  describe "Access page" do
    test "renders the access form", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/access/mnemonic")

      assert html =~ "Access Your Account"
      assert html =~ "Recovery Phrase"
    end

    test "shows word count on input", %{conn: conn} do
      {:ok, live_view, _html} = live(conn, ~p"/access/mnemonic")

      html =
        live_view
        |> form("#access-form", access: %{phrase: "one two three"})
        |> render_change()

      assert html =~ "3 of 12 words entered"
    end

    test "redirects to token URL on valid mnemonic", %{conn: conn} do
      {_user, raw_token, _login_token} = user_fixture_with_token()
      mnemonic = Mnemonic.encode(raw_token)

      {:ok, live_view, _html} = live(conn, ~p"/access/mnemonic")

      result =
        live_view
        |> form("#access-form", access: %{phrase: mnemonic})
        |> render_submit()

      assert {:error, {:live_redirect, %{to: "/u/" <> _token}}} = result
    end

    test "shows error for wrong word count", %{conn: conn} do
      {:ok, live_view, _html} = live(conn, ~p"/access/mnemonic")

      live_view
      |> form("#access-form", access: %{phrase: "one two three"})
      |> render_submit()

      html = render(live_view)
      assert html =~ "exactly 12 words"
    end

    test "shows error for invalid words", %{conn: conn} do
      {:ok, live_view, _html} = live(conn, ~p"/access/mnemonic")

      phrase = List.duplicate("notaword", 12) |> Enum.join(" ")

      live_view
      |> form("#access-form", access: %{phrase: phrase})
      |> render_submit()

      html = render(live_view)
      assert html =~ "not recognized"
    end

    test "has link to token login page", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/access/mnemonic")
      assert html =~ "Login with token instead"
    end
  end
end
