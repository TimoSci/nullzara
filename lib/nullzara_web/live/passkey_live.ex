defmodule NullzaraWeb.PasskeyLive do
  use NullzaraWeb, :live_view

  alias Nullzara.Webauthn

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-8">
        <.header>
          Passkey Login
          <:subtitle>Use a passkey to sign in or create an account.</:subtitle>
        </.header>

        <div id="passkey-auth" phx-hook=".PasskeyHook" class="space-y-4">
          <div class="flex flex-col gap-4 items-center">
            <.button
              id="passkey-login-btn"
              variant="primary"
              phx-click="start_authentication"
              disabled={@loading}
            >
              <.icon name="hero-finger-print-mini" /> Sign in with Passkey
            </.button>

            <span class="text-sm opacity-70">or</span>

            <.button
              id="passkey-register-btn"
              phx-click="start_registration"
              disabled={@loading}
            >
              <.icon name="hero-user-plus-mini" /> Create Account with Passkey
            </.button>
          </div>

          <p :if={@loading} class="text-center text-sm opacity-70">
            Waiting for authenticator...
          </p>

          <p :if={@error} class="text-center text-sm text-error">
            {@error}
          </p>
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".PasskeyHook">
      export default {
        mounted() {
          this.handleEvent("registration_challenge", async (data) => {
            try {
              const challenge = base64urlToBuffer(data.challenge);
              const userId = base64urlToBuffer(data.user_id);

              const credential = await navigator.credentials.create({
                publicKey: {
                  challenge: challenge,
                  rp: { name: data.rp_name, id: data.rp_id },
                  user: {
                    id: userId,
                    name: data.user_name,
                    displayName: data.user_display_name
                  },
                  pubKeyCredParams: [
                    { alg: -7, type: "public-key" },
                    { alg: -257, type: "public-key" }
                  ],
                  authenticatorSelection: {
                    residentKey: "preferred",
                    userVerification: "preferred"
                  },
                  timeout: 60000,
                  attestation: "none"
                }
              });

              this.pushEvent("registration_response", {
                attestation_object: bufferToBase64url(credential.response.attestationObject),
                client_data_json: bufferToBase64url(credential.response.clientDataJSON),
                raw_id: bufferToBase64url(credential.rawId)
              });
            } catch (e) {
              this.pushEvent("webauthn_error", { message: e.message || "Registration cancelled" });
            }
          });

          this.handleEvent("authentication_challenge", async (data) => {
            try {
              const options = {
                publicKey: {
                  challenge: base64urlToBuffer(data.challenge),
                  rpId: data.rp_id,
                  userVerification: "preferred",
                  timeout: 60000
                }
              };

              const assertion = await navigator.credentials.get(options);

              this.pushEvent("authentication_response", {
                credential_id: bufferToBase64url(assertion.rawId),
                authenticator_data: bufferToBase64url(assertion.response.authenticatorData),
                client_data_json: bufferToBase64url(assertion.response.clientDataJSON),
                signature: bufferToBase64url(assertion.response.signature)
              });
            } catch (e) {
              this.pushEvent("webauthn_error", { message: e.message || "Authentication cancelled" });
            }
          });
        }
      }

      function base64urlToBuffer(base64url) {
        const base64 = base64url.replace(/-/g, '+').replace(/_/g, '/');
        const pad = base64.length % 4 === 0 ? '' : '='.repeat(4 - (base64.length % 4));
        const binary = atob(base64 + pad);
        return Uint8Array.from(binary, c => c.charCodeAt(0)).buffer;
      }

      function bufferToBase64url(buffer) {
        const bytes = new Uint8Array(buffer);
        let binary = '';
        for (const b of bytes) binary += String.fromCharCode(b);
        return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
      }
      </script>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Passkey Login")
     |> assign(:loading, false)
     |> assign(:error, nil)
     |> assign(:challenge, nil)}
  end

  @impl true
  def handle_event("start_registration", _params, socket) do
    challenge = Webauthn.generate_registration_challenge()
    temp_user_id = :crypto.strong_rand_bytes(16)

    socket =
      socket
      |> assign(:challenge, challenge)
      |> assign(:loading, true)
      |> assign(:error, nil)
      |> push_event("registration_challenge", %{
        challenge: Base.url_encode64(challenge.bytes, padding: false),
        rp_id: Application.get_env(:wax_, :rp_id),
        rp_name: Application.get_env(:wax_, :rp_name, "Nullzara"),
        user_id: Base.url_encode64(temp_user_id, padding: false),
        user_name: "Anonymous",
        user_display_name: "Anonymous"
      })

    {:noreply, socket}
  end

  def handle_event("registration_response", params, socket) do
    challenge = socket.assigns.challenge

    attestation_object = Base.url_decode64!(params["attestation_object"], padding: false)
    client_data_json = Base.url_decode64!(params["client_data_json"], padding: false)
    raw_id = Base.url_decode64!(params["raw_id"], padding: false)

    case Webauthn.verify_registration(attestation_object, client_data_json, challenge) do
      {:ok, {authenticator_data, _attestation_result}} ->
        cose_key = authenticator_data.attested_credential_data.credential_public_key
        sign_count = authenticator_data.sign_count

        case Webauthn.store_credential(raw_id, cose_key, sign_count) do
          {:ok, user, _credential} ->
            token = Phoenix.Token.sign(NullzaraWeb.Endpoint, "passkey_auth", user.id)

            {:noreply,
             socket
             |> assign(:loading, false)
             |> redirect(to: "/access/passkey/complete?token=#{token}")}

          {:error, _reason} ->
            {:noreply,
             socket
             |> assign(:loading, false)
             |> assign(:error, "Could not create account.")}
        end

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:error, "Registration failed: #{inspect(reason)}")}
    end
  end

  def handle_event("start_authentication", _params, socket) do
    challenge = Webauthn.generate_authentication_challenge()

    socket =
      socket
      |> assign(:challenge, challenge)
      |> assign(:loading, true)
      |> assign(:error, nil)
      |> push_event("authentication_challenge", %{
        challenge: Base.url_encode64(challenge.bytes, padding: false),
        rp_id: Application.get_env(:wax_, :rp_id)
      })

    {:noreply, socket}
  end

  def handle_event("authentication_response", params, socket) do
    challenge = socket.assigns.challenge

    credential_id = Base.url_decode64!(params["credential_id"], padding: false)
    authenticator_data = Base.url_decode64!(params["authenticator_data"], padding: false)
    client_data_json = Base.url_decode64!(params["client_data_json"], padding: false)
    signature = Base.url_decode64!(params["signature"], padding: false)

    case Webauthn.verify_authentication(
           credential_id,
           authenticator_data,
           signature,
           client_data_json,
           challenge
         ) do
      {:ok, user} ->
        token = Phoenix.Token.sign(NullzaraWeb.Endpoint, "passkey_auth", user.id)

        {:noreply,
         socket
         |> assign(:loading, false)
         |> redirect(to: "/access/passkey/complete?token=#{token}")}

      {:error, :credential_not_found} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:error, "No passkey found. Create an account first.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:error, "Authentication failed: #{inspect(reason)}")}
    end
  end

  def handle_event("webauthn_error", %{"message" => message}, socket) do
    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:error, message)}
  end
end
