defmodule NullzaraWeb.WalletSettingsLive do
  use NullzaraWeb, :live_view

  alias Nullzara.Wallet
  alias NullzaraWeb.WalletComponents

  @nonce_max_age_ms 120_000

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-8">
        <.header>
          Connect Wallet
          <:subtitle>Sign a message with your wallet to link it to your account.</:subtitle>
        </.header>

        <WalletComponents.wallet_connector
          id="wallet-settings"
          wallets={@wallets}
          loading={@loading}
          error={@error}
        >
          <.button
            id="wallet-attach-btn"
            variant="primary"
            phx-click="connect_wallet"
            disabled={@loading}
          >
            <.icon name="hero-wallet-mini" /> Connect Wallet
          </.button>
          <:footer>
            <.button navigate={~p"/user/#{@current_user}/settings"}>
              Back to Settings
            </.button>
          </:footer>
        </WalletComponents.wallet_connector>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Connect Wallet")
     |> assign(:loading, false)
     |> assign(:error, nil)
     |> assign(:wallets, [])
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
      |> assign(:wallets, [])
      |> push_event("request_accounts", %{})

    {:noreply, socket}
  end

  # The browser found more than one wallet extension: let the visitor choose.
  def handle_event("wallets_found", params, socket) do
    case WalletComponents.normalize_wallets(params) do
      [] ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:error, WalletComponents.no_wallet_message())}

      wallets ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:wallets, wallets)}
    end
  end

  def handle_event("choose_wallet", %{"id" => id}, socket) do
    if Enum.any?(socket.assigns.wallets, &(&1.id == id)) do
      {:noreply,
       socket
       |> assign(:loading, true)
       |> assign(:error, nil)
       |> assign(:wallets, [])
       |> push_event("request_accounts", %{wallet: id})}
    else
      {:noreply, socket}
    end
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
    user = socket.assigns.current_user
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

          case Wallet.attach_credential(user, verified_address) do
            {:ok, _credential} ->
              {:noreply,
               socket
               |> assign(:loading, false)
               |> put_flash(:info, "Wallet connected successfully.")
               |> redirect(to: ~p"/user/#{user}/settings")}

            {:error, _changeset} ->
              {:noreply,
               socket
               |> assign(:loading, false)
               |> assign(
                 :error,
                 "Could not connect wallet. It may already be linked to another account."
               )}
          end

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
     |> assign(:wallets, [])
     |> assign(:error, message)}
  end
end
