defmodule NullzaraWeb.WalletComponents do
  @moduledoc """
  The browser side of wallet sign-in, shared by the wallet login page and
  the wallet settings page.

  Wallet extensions are found with EIP-6963 (each extension announces
  itself), so that a visitor with several extensions can choose one.
  `window.ethereum` is only a fallback for wallets that do not announce
  themselves, because extensions overwrite each other there.

  Events between the hook and the LiveView:

    * server → hook `"request_accounts"` with an optional `wallet` id
    * hook → server `"wallets_found"` when there is more than one wallet
    * hook → server `"wallet_connected"`, `"message_signed"`, `"wallet_error"`
    * server → hook `"sign_message"`
  """
  use Phoenix.Component

  import NullzaraWeb.CoreComponents, only: [icon: 1]

  @max_wallets 10
  @max_id_bytes 200
  @max_name_length 50
  @max_icon_bytes 100_000

  @no_wallet_message "No wallet detected. Install MetaMask or another Ethereum wallet."

  @doc "The message shown when the browser has no usable wallet."
  def no_wallet_message, do: @no_wallet_message

  @doc """
  Turns the `"wallets_found"` payload sent by the browser into a list of
  `%{id: binary, name: binary, icon: binary | nil}`.

  The payload comes from browser extensions, so nothing in it is trusted:
  entries of the wrong shape are dropped, names are shortened, and an icon
  is kept only if it is an image data URI of a reasonable size.
  """
  def normalize_wallets(%{"wallets" => wallets}) when is_list(wallets) do
    wallets
    |> Enum.flat_map(&normalize_wallet/1)
    |> Enum.uniq_by(& &1.id)
    |> Enum.take(@max_wallets)
  end

  def normalize_wallets(_params), do: []

  defp normalize_wallet(%{"id" => id, "name" => name} = wallet)
       when is_binary(id) and is_binary(name) and id != "" and byte_size(id) <= @max_id_bytes do
    name =
      case name |> String.trim() |> String.slice(0, @max_name_length) do
        "" -> "Wallet"
        trimmed -> trimmed
      end

    [%{id: id, name: name, icon: normalize_icon(wallet["icon"])}]
  end

  defp normalize_wallet(_wallet), do: []

  defp normalize_icon("data:image/" <> _ = icon) when byte_size(icon) <= @max_icon_bytes, do: icon
  defp normalize_icon(_icon), do: nil

  @doc """
  Renders the wallet hook, the wallet chooser, and the waiting and error
  messages. The inner block holds the button that starts the flow.
  """
  attr :id, :string, required: true
  attr :wallets, :list, default: []
  attr :loading, :boolean, default: false
  attr :error, :string, default: nil
  slot :inner_block, required: true
  slot :footer

  def wallet_connector(assigns) do
    ~H"""
    <div id={@id} phx-hook=".WalletHook" class="space-y-4">
      <div class="flex flex-col gap-4 items-center">
        {render_slot(@inner_block)}
      </div>

      <div :if={@wallets != []} id={"#{@id}-chooser"} class="flex flex-col gap-2 items-center">
        <p class="text-sm opacity-70">Several wallets found. Choose one:</p>
        <button
          :for={{wallet, index} <- Enum.with_index(@wallets)}
          id={"#{@id}-choose-#{index}"}
          type="button"
          phx-click="choose_wallet"
          phx-value-id={wallet.id}
          class="btn btn-primary btn-soft w-64 max-w-full justify-start gap-3"
        >
          <img :if={wallet.icon} src={wallet.icon} alt="" class="size-6 rounded" />
          <.icon :if={!wallet.icon} name="hero-wallet-mini" class="size-6" />
          <span class="truncate">{wallet.name}</span>
        </button>
      </div>

      <p :if={@loading} class="text-center text-sm opacity-70">
        Waiting for wallet...
      </p>

      <p :if={@error} class="text-center text-sm text-error">
        {@error}
      </p>

      <div :if={@footer != []} class="flex flex-col gap-4 items-center">
        {render_slot(@footer)}
      </div>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".WalletHook">
      const NO_WALLET = "No wallet detected. Install MetaMask or another Ethereum wallet.";

      export default {
        mounted() {
          // Wallets announced through EIP-6963, keyed by their uuid.
          this.providers = new Map();
          this.provider = null;

          this.onAnnounce = (event) => {
            const { info, provider } = event.detail || {};
            if (info && info.uuid && provider) {
              this.providers.set(info.uuid, { info, provider });
            }
          };

          this.onAccountsChanged = (accounts) => {
            if (accounts.length > 0) {
              this.pushEvent("wallet_connected", { address: accounts[0] });
            }
          };

          window.addEventListener("eip6963:announceProvider", this.onAnnounce);
          window.dispatchEvent(new Event("eip6963:requestProvider"));

          this.handleEvent("request_accounts", async (data) => {
            try {
              const provider = await this.pickProvider(data.wallet);
              if (!provider) return;

              this.useProvider(provider);

              const accounts = await provider.request({
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

          this.handleEvent("sign_message", async (data) => {
            try {
              if (!this.provider) {
                this.pushEvent("wallet_error", { message: NO_WALLET });
                return;
              }

              const signature = await this.provider.request({
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
        },

        destroyed() {
          window.removeEventListener("eip6963:announceProvider", this.onAnnounce);
          this.useProvider(null);
        },

        // Returns the provider to use, or null after telling the server why
        // there is none yet (no wallet, or the visitor has to choose).
        async pickProvider(walletId) {
          if (walletId) {
            const chosen = this.providers.get(walletId);
            if (chosen) return chosen.provider;

            this.pushEvent("wallet_error", {
              message: "That wallet is no longer available. Please try again."
            });
            return null;
          }

          // Ask again, and give slow extensions a moment to answer.
          window.dispatchEvent(new Event("eip6963:requestProvider"));
          await new Promise((resolve) => setTimeout(resolve, 100));

          const found = Array.from(this.providers.values());

          if (found.length > 1) {
            this.pushEvent("wallets_found", {
              wallets: found.map(({ info }) => ({
                id: info.uuid,
                name: info.name,
                icon: info.icon
              }))
            });
            return null;
          }

          if (found.length === 1) return found[0].provider;
          if (window.ethereum) return window.ethereum;

          this.pushEvent("wallet_error", { message: NO_WALLET });
          return null;
        },

        useProvider(provider) {
          if (this.provider === provider) return;

          if (this.provider && this.provider.removeListener) {
            this.provider.removeListener("accountsChanged", this.onAccountsChanged);
          }

          this.provider = provider;

          if (provider && provider.on) {
            provider.on("accountsChanged", this.onAccountsChanged);
          }
        }
      }
    </script>
    """
  end
end
