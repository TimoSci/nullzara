defmodule NullzaraWeb.PasskeyLiveTest do
  use NullzaraWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "PasskeyLive" do
    test "renders the passkey login page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/access/passkey")

      assert html =~ "Passkey Login"
      assert html =~ "Sign in with Passkey"
      assert html =~ "Create Account with Passkey"
    end

    test "start_registration assigns a challenge and sets loading", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/access/passkey")

      assert view
             |> element("#passkey-register-btn")
             |> render_click() =~ "Waiting for authenticator"
    end

    test "start_authentication assigns a challenge and sets loading", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/access/passkey")

      assert view
             |> element("#passkey-login-btn")
             |> render_click() =~ "Waiting for authenticator"
    end

    test "webauthn_error displays the error message", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/access/passkey")

      assert render_hook(view, "webauthn_error", %{"message" => "User cancelled"}) =~
               "User cancelled"
    end

    test "a failed registration shows a plain message, not internal details", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/access/passkey")
      view |> element("#passkey-register-btn") |> render_click()

      client_data =
        Base.url_encode64(
          ~s|{"type":"webauthn.get","challenge":"AAAA","origin":"http://localhost:4000"}|,
          padding: false
        )

      html =
        render_hook(view, "registration_response", %{
          "attestation_object" => "AAAA",
          "client_data_json" => client_data,
          "raw_id" => "AAAA"
        })

      assert html =~ "Passkey registration failed. Please try again."
      refute html =~ "Wax"
      refute html =~ "%{"
    end
  end
end
