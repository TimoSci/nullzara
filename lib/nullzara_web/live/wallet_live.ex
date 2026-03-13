defmodule NullzaraWeb.WalletLive do
  use NullzaraWeb, :live_view

  alias Nullzara.Wallet

  @nonce_max_age_ms 120_000

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-8">
        <.header>
          Wallet Login
          <:subtitle>Use an Ethereum wallet to sign in or create an account.</:subtitle>
        </.header>

        <div id="wallet-auth" phx-hook=".WalletHook" class="space-y-4">
          <div class="flex flex-col gap-4 items-center">
            <.button
              id="wallet-connect-btn"
              variant="primary"
              phx-click="connect_wallet"
              disabled={@loading}
            >
              <.icon name="hero-wallet-mini" /> Sign in with Wallet
            </.button>
          </div>

          <p :if={@loading} class="text-center text-sm opacity-70">
            Waiting for wallet...
          </p>

          <p :if={@error} class="text-center text-sm text-error">
            {@error}
          </p>
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".WalletHook">
        export default {
          mounted() {
            this.handleEvent("request_accounts", async (_data) => {
              try {
                if (!window.ethereum) {
                  this.pushEvent("wallet_error", {
                    message: "No wallet detected. Install MetaMask or another Ethereum wallet."
                  });
                  return;
                }

                const accounts = await window.ethereum.request({
                  method: "eth_requestAccounts"
                });

                if (accounts.length === 0) {
                  this.pushEvent("wallet_error", { message: "No accounts found." });
                  return;
                }

                this.pushEvent("wallet_connected", { address: accounts[0] });
              } catch (e) {
                this.pushEvent("wallet_error", {
                  message: e.message || "Wallet connection cancelled"
                });
              }
            });

            if (window.ethereum) {
              window.ethereum.on("accountsChanged", (accounts) => {
                if (accounts.length > 0) {
                  this.pushEvent("wallet_connected", { address: accounts[0] });
                }
              });
            }

            this.handleEvent("sign_message", async (data) => {
              try {
                const signature = await window.ethereum.request({
                  method: "personal_sign",
                  params: [data.message, data.address]
                });

                this.pushEvent("message_signed", { signature: signature });
              } catch (e) {
                this.pushEvent("wallet_error", {
                  message: e.message || "Signing cancelled"
                });
              }
            });
          }
        }
      </script>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Wallet Login")
     |> assign(:loading, false)
     |> assign(:error, nil)
     |> assign(:nonce, nil)
     |> assign(:nonce_issued_at, nil)
     |> assign(:address, nil)}
  end

  @impl true
  def handle_event("connect_wallet", _params, socket) do
    socket =
      socket
      |> assign(:loading, true)
      |> assign(:error, nil)
      |> push_event("request_accounts", %{})

    {:noreply, socket}
  end

  def handle_event("wallet_connected", %{"address" => address}, socket) do
    nonce = Wallet.generate_nonce()
    message = Wallet.build_sign_message(nonce)

    socket =
      socket
      |> assign(:nonce, nonce)
      |> assign(:nonce_issued_at, System.monotonic_time(:millisecond))
      |> assign(:address, address)
      |> push_event("sign_message", %{message: message, address: address})

    {:noreply, socket}
  end

  def handle_event("message_signed", %{"signature" => signature}, socket) do
    address = socket.assigns.address
    nonce = socket.assigns.nonce
    nonce_issued_at = socket.assigns.nonce_issued_at

    age = System.monotonic_time(:millisecond) - nonce_issued_at

    if age > @nonce_max_age_ms do
      {:noreply,
       socket
       |> assign(:loading, false)
       |> assign(:nonce, nil)
       |> assign(:error, "Nonce expired. Please try again.")}
    else
      message = Wallet.build_sign_message(nonce)

      case Wallet.verify_signature(signature, message, address) do
        {:ok, verified_address} ->
          socket = assign(socket, :nonce, nil)

          user =
            case Wallet.get_credential_by_address(verified_address) do
              {:ok, credential} ->
                credential.user

              {:error, :not_found} ->
                {:ok, user, _credential} = Wallet.store_credential(verified_address)
                user
            end

          token = Phoenix.Token.sign(NullzaraWeb.Endpoint, "wallet_auth", user.id)

          {:noreply,
           socket
           |> assign(:loading, false)
           |> redirect(to: "/access/wallet/complete?token=#{token}")}

        {:error, _reason} ->
          {:noreply,
           socket
           |> assign(:loading, false)
           |> assign(:nonce, nil)
           |> assign(:error, "Signature verification failed. Please try again.")}
      end
    end
  end

  def handle_event("wallet_error", %{"message" => message}, socket) do
    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:error, message)}
  end
end
