# Wallet Authentication Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to sign in or create accounts using an Ethereum wallet (MetaMask + any EIP-1193 wallet), with automatic account creation on first use and attach/detach from settings.

**Architecture:** Server generates a nonce, the wallet signs it via `personal_sign` (EIP-191), and the server recovers the Ethereum address from the signature using `ex_secp256k1` + `ex_keccak`. A `wallet_credentials` table stores one wallet address per user. A LiveView at `/access/wallet` handles sign-in/registration, a controller handles session setup, and a separate LiveView at `/user/:id/settings/wallet` handles attaching a wallet to an existing account.

**Tech Stack:** `ex_secp256k1` (EC recovery NIF), `ex_keccak` (keccak256 NIF), Phoenix LiveView (colocated JS hooks), `window.ethereum` (EIP-1193 provider).

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `mix.exs` | Modify | Add `ex_secp256k1` and `ex_keccak` deps |
| `priv/repo/migrations/*_create_wallet_credentials.exs` | Create | Migration for wallet_credentials table |
| `lib/nullzara/wallet/credential.ex` | Create | Ecto schema for wallet_credentials |
| `lib/nullzara/wallet.ex` | Create | Context: signature verification, credential CRUD |
| `lib/nullzara/users/user.ex` | Modify | Add `has_one :wallet_credential` |
| `lib/nullzara_web/live/wallet_live.ex` | Create | LiveView for login/registration with colocated JS hook |
| `lib/nullzara_web/controllers/wallet_controller.ex` | Create | Completion controller (sets session) |
| `lib/nullzara_web/router.ex` | Modify | Add wallet routes |
| `lib/nullzara_web/components/layouts.ex` | Modify | Add "Login with Wallet" navbar button |
| `lib/nullzara_web/controllers/settings_html/_settings.html.heex` | Modify | Add wallet section to settings |
| `lib/nullzara_web/controllers/settings_controller.ex` | Modify | Add `detach_wallet` action |
| `lib/nullzara_web/live/wallet_settings_live.ex` | Create | LiveView for attaching wallet from settings |
| `test/nullzara/wallet_test.exs` | Create | Context unit tests |
| `test/nullzara_web/live/wallet_live_test.exs` | Create | LiveView tests |
| `test/nullzara_web/controllers/wallet_controller_test.exs` | Create | Controller tests |
| `test/nullzara_web/live/wallet_settings_live_test.exs` | Create | Settings wallet attach tests |

---

## Task 1: Add dependencies

**Files:**
- Modify: `mix.exs`

- [ ] **Step 1: Add ex_secp256k1 and ex_keccak to deps in mix.exs**

In the `deps` function, add a trailing comma after `{:wax_, "~> 0.7"}`, then add:

```elixir
{:ex_secp256k1, "~> 0.7"},
{:ex_keccak, "~> 0.7"}
```

- [ ] **Step 2: Run mix deps.get**

Run: `mix deps.get`
Expected: Both packages download successfully.

- [ ] **Step 3: Verify compilation**

Run: `mix compile`
Expected: Compiles with no errors.

- [ ] **Step 4: Commit**

```bash
git add mix.exs mix.lock
git commit -m "Add ex_secp256k1 and ex_keccak dependencies for wallet auth"
```

---

## Task 2: Create wallet_credentials migration and schema

**Files:**
- Create: `priv/repo/migrations/*_create_wallet_credentials.exs` (via `mix ecto.gen.migration`)
- Create: `lib/nullzara/wallet/credential.ex`
- Modify: `lib/nullzara/users/user.ex`

- [ ] **Step 1: Generate migration**

Run: `mix ecto.gen.migration create_wallet_credentials`

- [ ] **Step 2: Write the migration**

Edit the generated migration file:

```elixir
defmodule Nullzara.Repo.Migrations.CreateWalletCredentials do
  use Ecto.Migration

  def change do
    create table(:wallet_credentials) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :address, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:wallet_credentials, [:user_id])
    create unique_index(:wallet_credentials, [:address])
  end
end
```

- [ ] **Step 3: Run the migration**

Run: `mix ecto.migrate`
Expected: Migration runs successfully.

- [ ] **Step 4: Write the Credential schema**

Create `lib/nullzara/wallet/credential.ex`:

```elixir
defmodule Nullzara.Wallet.Credential do
  use Ecto.Schema
  import Ecto.Changeset

  schema "wallet_credentials" do
    belongs_to :user, Nullzara.Users.User
    field :address, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [:address])
    |> validate_required([:address])
    |> update_change(:address, &String.downcase/1)
    |> unique_constraint(:address)
    |> unique_constraint(:user_id)
    |> foreign_key_constraint(:user_id)
  end
end
```

- [ ] **Step 5: Add has_one to User schema**

In `lib/nullzara/users/user.ex`, add inside the `schema "users"` block, after the `has_many :webauthn_credentials` line:

```elixir
has_one :wallet_credential, Nullzara.Wallet.Credential
```

- [ ] **Step 6: Verify compilation**

Run: `mix compile`
Expected: Compiles with no errors.

- [ ] **Step 7: Commit**

```bash
git add priv/repo/migrations/*_create_wallet_credentials.exs lib/nullzara/wallet/credential.ex lib/nullzara/users/user.ex
git commit -m "Add wallet_credentials table and schema"
```

---

## Task 3: Create Wallet context module with tests

**Files:**
- Create: `test/nullzara/wallet_test.exs`
- Create: `lib/nullzara/wallet.ex`

The context handles EIP-191 signature verification and credential CRUD. Key functions:
- `generate_nonce/0` — returns 32 random hex bytes
- `build_sign_message/1` — wraps nonce in human-readable message
- `verify_signature/3` — recovers address from signature + message, compares to claimed address
- `store_credential/1` — creates user + wallet credential in a transaction
- `get_credential_by_address/1` — looks up credential with preloaded user
- `attach_credential/2` — attaches wallet to existing user
- `detach_credential/1` — removes wallet credential

- [ ] **Step 1: Write tests for the context**

Create `test/nullzara/wallet_test.exs`:

```elixir
defmodule Nullzara.WalletTest do
  use Nullzara.DataCase, async: true

  alias Nullzara.Wallet

  describe "generate_nonce/0" do
    test "returns a 64-character hex string" do
      nonce = Wallet.generate_nonce()
      assert byte_size(nonce) == 64
      assert Regex.match?(~r/\A[0-9a-f]{64}\z/, nonce)
    end

    test "returns unique values" do
      nonce1 = Wallet.generate_nonce()
      nonce2 = Wallet.generate_nonce()
      refute nonce1 == nonce2
    end
  end

  describe "build_sign_message/1" do
    test "wraps nonce in human-readable message" do
      message = Wallet.build_sign_message("abc123")
      assert message == "Sign in to Nullzara\n\nNonce: abc123"
    end
  end

  describe "verify_signature/3" do
    test "recovers correct address from a valid signature" do
      # Generate a test keypair
      private_key = :crypto.strong_rand_bytes(32)
      {:ok, public_key} = ExSecp256k1.create_public_key(private_key)

      # Derive Ethereum address from public key
      # public_key is 65 bytes (0x04 prefix + 64 bytes), strip prefix
      <<4, key_data::binary-size(64)>> = public_key
      <<_::binary-size(12), address_bytes::binary-size(20)>> = ExKeccak.hash_256(key_data)
      expected_address = "0x" <> Base.encode16(address_bytes, case: :lower)

      # Build and sign message
      nonce = Wallet.generate_nonce()
      message = Wallet.build_sign_message(nonce)

      # EIP-191 prefix
      prefixed = "\x19Ethereum Signed Message:\n#{byte_size(message)}" <> message
      hash = ExKeccak.hash_256(prefixed)

      {:ok, {r, s, v}} = ExSecp256k1.sign(hash, private_key)

      # Reconstruct 65-byte signature as MetaMask would return it (r + s + v)
      signature = r <> s <> <<v + 27>>
      hex_signature = "0x" <> Base.encode16(signature, case: :lower)

      assert {:ok, recovered} = Wallet.verify_signature(hex_signature, message, expected_address)
      assert String.downcase(recovered) == String.downcase(expected_address)
    end

    test "rejects signature from wrong address" do
      private_key = :crypto.strong_rand_bytes(32)

      nonce = Wallet.generate_nonce()
      message = Wallet.build_sign_message(nonce)

      prefixed = "\x19Ethereum Signed Message:\n#{byte_size(message)}" <> message
      hash = ExKeccak.hash_256(prefixed)

      {:ok, {r, s, v}} = ExSecp256k1.sign(hash, private_key)

      signature = r <> s <> <<v + 27>>
      hex_signature = "0x" <> Base.encode16(signature, case: :lower)

      assert {:error, :address_mismatch} =
               Wallet.verify_signature(hex_signature, message, "0x0000000000000000000000000000000000000000")
    end
  end

  describe "store_credential/1" do
    test "creates a user and wallet credential" do
      address = "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)

      assert {:ok, user, credential} = Wallet.store_credential(address)
      assert user.name == "Anonymous"
      assert user.mnemonic_hash != nil
      assert user.token_hash != nil
      assert credential.address == String.downcase(address)
      assert credential.user_id == user.id
    end
  end

  describe "get_credential_by_address/1" do
    test "returns credential with preloaded user" do
      address = "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
      {:ok, _user, _credential} = Wallet.store_credential(address)

      assert {:ok, found} = Wallet.get_credential_by_address(address)
      assert found.address == String.downcase(address)
      assert %Nullzara.Users.User{} = found.user
    end

    test "returns error for unknown address" do
      assert {:error, :not_found} =
               Wallet.get_credential_by_address("0x0000000000000000000000000000000000000000")
    end
  end

  describe "attach_credential/2" do
    test "attaches wallet to existing user" do
      {:ok, user} = Nullzara.Users.create_user_with_token(%{name: "Test"})
      address = "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)

      assert {:ok, credential} = Wallet.attach_credential(user, address)
      assert credential.user_id == user.id
      assert credential.address == String.downcase(address)
    end

    test "returns error if user already has a wallet" do
      address1 = "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
      {:ok, user, _cred} = Wallet.store_credential(address1)

      address2 = "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
      assert {:error, _changeset} = Wallet.attach_credential(user, address2)
    end
  end

  describe "detach_credential/1" do
    test "removes wallet credential" do
      address = "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
      {:ok, _user, credential} = Wallet.store_credential(address)

      assert {:ok, _} = Wallet.detach_credential(credential)
      assert {:error, :not_found} = Wallet.get_credential_by_address(address)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/nullzara/wallet_test.exs`
Expected: Failures because `Nullzara.Wallet` module doesn't exist yet.

- [ ] **Step 3: Write the Wallet context**

Create `lib/nullzara/wallet.ex`:

```elixir
defmodule Nullzara.Wallet do
  @moduledoc """
  Context for Ethereum wallet authentication via EIP-191 personal_sign.
  """

  alias Nullzara.Repo
  alias Nullzara.Users.User
  alias Nullzara.Wallet.Credential

  import Ecto.Query

  @sign_message_prefix "Sign in to Nullzara\n\nNonce: "

  def generate_nonce do
    :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
  end

  def build_sign_message(nonce) do
    @sign_message_prefix <> nonce
  end

  def verify_signature(hex_signature, message, claimed_address) do
    with {:ok, address} <- recover_address(hex_signature, message) do
      if String.downcase(address) == String.downcase(claimed_address) do
        {:ok, address}
      else
        {:error, :address_mismatch}
      end
    end
  end

  def store_credential(address) do
    Repo.transaction(fn ->
      {:ok, user} =
        %User{}
        |> User.registration_changeset(%{name: "Anonymous"})
        |> Repo.insert()

      {:ok, credential} =
        %Credential{}
        |> Credential.changeset(%{address: address})
        |> Ecto.Changeset.put_change(:user_id, user.id)
        |> Repo.insert()

      {user, credential}
    end)
    |> case do
      {:ok, {user, credential}} -> {:ok, user, credential}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_credential_by_address(address) do
    query =
      from c in Credential,
        where: c.address == ^String.downcase(address),
        preload: [:user]

    case Repo.one(query) do
      nil -> {:error, :not_found}
      credential -> {:ok, credential}
    end
  end

  def attach_credential(user, address) do
    %Credential{}
    |> Credential.changeset(%{address: address})
    |> Ecto.Changeset.put_change(:user_id, user.id)
    |> Repo.insert()
  end

  def detach_credential(credential) do
    Repo.delete(credential)
  end

  # --- Private: EIP-191 signature recovery ---

  defp recover_address(hex_signature, message) do
    # Strip 0x prefix and decode
    raw_sig = hex_signature |> String.trim_leading("0x") |> Base.decode16!(case: :mixed)

    # Split into r (32), s (32), v (1)
    <<r::binary-size(32), s::binary-size(32), v>> = raw_sig

    # Normalize v: Ethereum uses 27/28, ex_secp256k1 expects 0/1
    recovery_id = if v >= 27, do: v - 27, else: v

    # EIP-191 prefixed hash
    prefixed = "\x19Ethereum Signed Message:\n#{byte_size(message)}" <> message
    hash = ExKeccak.hash_256(prefixed)

    # Recover public key
    case ExSecp256k1.recover(hash, r, s, recovery_id) do
      {:ok, public_key} ->
        # public_key is 65 bytes: 0x04 prefix + 64 bytes of key data
        <<4, key_data::binary-size(64)>> = public_key
        <<_::binary-size(12), address_bytes::binary-size(20)>> = ExKeccak.hash_256(key_data)
        {:ok, "0x" <> Base.encode16(address_bytes, case: :lower)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/nullzara/wallet_test.exs`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/nullzara/wallet.ex test/nullzara/wallet_test.exs
git commit -m "Add Wallet context with EIP-191 signature verification and credential CRUD"
```

---

## Task 4: Create WalletLive LiveView with colocated JS hook

**Files:**
- Create: `lib/nullzara_web/live/wallet_live.ex`

The LiveView handles two flows: sign-in (existing wallet) and registration (new wallet → auto-create user). The JS hook uses `window.ethereum` (injected by MetaMask / any EIP-1193 wallet).

- [ ] **Step 1: Create the WalletLive module**

Create `lib/nullzara_web/live/wallet_live.ex`:

```elixir
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

    # Check nonce expiry
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
          # Clear nonce (single-use)
          socket = assign(socket, :nonce, nil)

          # Find or create user
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
```

- [ ] **Step 2: Verify compilation**

Run: `mix compile`
Expected: Compiles with no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/nullzara_web/live/wallet_live.ex
git commit -m "Add WalletLive with colocated EIP-1193 JS hook"
```

---

## Task 5: Add wallet controller, routes, navbar button, and tests

**Files:**
- Create: `lib/nullzara_web/controllers/wallet_controller.ex`
- Modify: `lib/nullzara_web/router.ex`
- Modify: `lib/nullzara_web/components/layouts.ex`
- Create: `test/nullzara_web/live/wallet_live_test.exs`
- Create: `test/nullzara_web/controllers/wallet_controller_test.exs`

- [ ] **Step 1: Create the WalletController**

Create `lib/nullzara_web/controllers/wallet_controller.ex`:

```elixir
defmodule NullzaraWeb.WalletController do
  use NullzaraWeb, :controller

  alias Nullzara.Users

  def complete(conn, %{"token" => token}) do
    case Phoenix.Token.verify(NullzaraWeb.Endpoint, "wallet_auth", token, max_age: 60) do
      {:ok, user_id} ->
        user = Users.get_user!(user_id)

        conn
        |> put_session(:user_id, user.id)
        |> configure_session(renew: true)
        |> redirect(to: ~p"/user/#{user}/dashboard")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Wallet session expired. Please try again.")
        |> redirect(to: ~p"/access/wallet")
    end
  end
end
```

- [ ] **Step 2: Add routes**

In `lib/nullzara_web/router.ex`, add the LiveView route to the first public browser scope (after the `live "/access/passkey"` line):

```elixir
live "/access/wallet", WalletLive
```

Add the completion route to the existing `rate_limit_verify` scope (after the `get "/u/:token"` line):

```elixir
get "/access/wallet/complete", WalletController, :complete
```

- [ ] **Step 3: Add "Login with Wallet" button to layout**

In `lib/nullzara_web/components/layouts.ex`, add after the "Login with Passkey" `<li>` block:

```elixir
<li :if={!@current_user}>
  <.button navigate={~p"/access/wallet"}>
    <.icon name="hero-wallet-mini" /> Login with Wallet
  </.button>
</li>
```

- [ ] **Step 4: Create LiveView tests**

Create `test/nullzara_web/live/wallet_live_test.exs`:

```elixir
defmodule NullzaraWeb.WalletLiveTest do
  use NullzaraWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "WalletLive" do
    test "renders the wallet login page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/access/wallet")

      assert html =~ "Wallet Login"
      assert html =~ "Sign in with Wallet"
    end

    test "connect_wallet sets loading state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/access/wallet")

      assert view
             |> element("#wallet-connect-btn")
             |> render_click() =~ "Waiting for wallet"
    end

    test "wallet_error displays the error message", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/access/wallet")

      assert render_hook(view, "wallet_error", %{"message" => "User rejected"}) =~
               "User rejected"
    end
  end
end
```

- [ ] **Step 5: Create controller tests**

Create `test/nullzara_web/controllers/wallet_controller_test.exs`:

```elixir
defmodule NullzaraWeb.WalletControllerTest do
  use NullzaraWeb.ConnCase, async: true

  alias Nullzara.Users

  describe "complete/2" do
    test "logs in user with valid token", %{conn: conn} do
      {:ok, user} = Users.create_user_with_token(%{name: "Test"})
      token = Phoenix.Token.sign(NullzaraWeb.Endpoint, "wallet_auth", user.id)

      conn = get(conn, ~p"/access/wallet/complete?token=#{token}")

      assert redirected_to(conn) =~ "/user/"
      assert get_session(conn, :user_id) == user.id
    end

    test "rejects invalid token", %{conn: conn} do
      conn = get(conn, ~p"/access/wallet/complete?token=invalid_token")

      assert redirected_to(conn) == "/access/wallet"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "expired"
    end
  end
end
```

- [ ] **Step 6: Run all tests**

Run: `mix test`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/nullzara_web/controllers/wallet_controller.ex lib/nullzara_web/router.ex lib/nullzara_web/components/layouts.ex test/nullzara_web/live/wallet_live_test.exs test/nullzara_web/controllers/wallet_controller_test.exs
git commit -m "Add wallet routes, completion controller, navbar button, and tests"
```

---

## Task 6: Add wallet section to settings page and detach action

**Files:**
- Modify: `lib/nullzara_web/controllers/settings_controller.ex`
- Modify: `lib/nullzara_web/controllers/settings_html/_settings.html.heex`

The settings page shows the connected wallet address (if any) with a "Detach" button, or a "Connect Wallet" link if no wallet is attached. Detach is a simple form POST to the settings controller.

- [ ] **Step 1: Add detach_wallet action to SettingsController**

In `lib/nullzara_web/controllers/settings_controller.ex`, add the alias and preload the wallet credential:

Add after the existing aliases:

```elixir
alias Nullzara.Wallet
```

Modify the `show` action to preload the wallet credential. Change:

```elixir
def show(conn, _params) do
  user = conn.assigns.current_user
```

To:

```elixir
def show(conn, _params) do
  user = conn.assigns.current_user |> Nullzara.Repo.preload(:wallet_credential)
```

Also update the `update` action's error path to preload:

```elixir
{:error, changeset} ->
  mnemonic_token = get_session(conn, :mnemonic_token)
  mnemonic = if mnemonic_token, do: Mnemonic.encode(mnemonic_token)
  user = Nullzara.Repo.preload(user, :wallet_credential)
  render(conn, :show, user: user, changeset: changeset, mnemonic: mnemonic)
```

Add the `detach_wallet` action:

```elixir
def detach_wallet(conn, _params) do
  user = conn.assigns.current_user |> Nullzara.Repo.preload(:wallet_credential)

  case user.wallet_credential do
    nil ->
      conn
      |> put_flash(:error, "No wallet connected.")
      |> redirect(to: ~p"/user/#{user}/settings")

    credential ->
      {:ok, _} = Wallet.detach_credential(credential)

      conn
      |> put_flash(:info, "Wallet disconnected.")
      |> redirect(to: ~p"/user/#{user}/settings")
  end
end
```

- [ ] **Step 2: Add route for detach_wallet**

In `lib/nullzara_web/router.ex`, in the authenticated scope (with `pipe_through [:browser, :require_auth]`), add after the `delete "/user/:id/settings"` line:

```elixir
delete "/user/:id/settings/wallet", SettingsController, :detach_wallet
```

- [ ] **Step 3: Add wallet section to settings template**

In `lib/nullzara_web/controllers/settings_html/_settings.html.heex`, add after the "Login Token" section (before the "Delete Account" section):

```heex
<div class="rounded-box border border-base-300 bg-base-200/50 p-6 space-y-4">
  <h2 class="text-lg font-semibold">Wallet</h2>
  <div :if={@user.wallet_credential}>
    <p class="text-sm text-base-content/70">
      Connected wallet address:
    </p>
    <p class="font-mono text-sm bg-base-300/50 rounded-box p-3 select-all">
      {@user.wallet_credential.address}
    </p>
    <.form for={%{}} action={~p"/user/#{@user}/settings/wallet"} method="delete" class="mt-4">
      <.button type="submit" data-confirm="Disconnect this wallet? You can connect a different one later.">
        Disconnect Wallet
      </.button>
    </.form>
  </div>
  <div :if={!@user.wallet_credential}>
    <p class="text-sm text-base-content/70">
      No wallet connected. Connect an Ethereum wallet to sign in with it.
    </p>
    <.button navigate={~p"/user/#{@user}/settings/wallet"} class="mt-4">
      <.icon name="hero-wallet-mini" /> Connect Wallet
    </.button>
  </div>
</div>
```

- [ ] **Step 4: Run all tests**

Run: `mix test`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/nullzara_web/controllers/settings_controller.ex lib/nullzara_web/controllers/settings_html/_settings.html.heex lib/nullzara_web/router.ex
git commit -m "Add wallet section to settings with attach/detach support"
```

---

## Task 7: Create WalletSettingsLive for attaching wallet to existing account

**Files:**
- Create: `lib/nullzara_web/live/wallet_settings_live.ex`
- Modify: `lib/nullzara_web/router.ex`

This LiveView reuses the same sign-message flow as WalletLive, but attaches the wallet to the currently authenticated user instead of creating a new one.

- [ ] **Step 1: Create WalletSettingsLive**

Create `lib/nullzara_web/live/wallet_settings_live.ex`:

```elixir
defmodule NullzaraWeb.WalletSettingsLive do
  use NullzaraWeb, :live_view

  alias Nullzara.Wallet

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

        <div id="wallet-settings" phx-hook=".WalletSettingsHook" class="space-y-4">
          <div class="flex flex-col gap-4 items-center">
            <.button
              id="wallet-attach-btn"
              variant="primary"
              phx-click="connect_wallet"
              disabled={@loading}
            >
              <.icon name="hero-wallet-mini" /> Connect Wallet
            </.button>

            <.button navigate={~p"/user/#{@current_user}/settings"}>
              Back to Settings
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

      <script :type={Phoenix.LiveView.ColocatedHook} name=".WalletSettingsHook">
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
     |> assign(:page_title, "Connect Wallet")
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
               |> assign(:error, "Could not connect wallet. It may already be linked to another account.")}
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
     |> assign(:error, message)}
  end
end
```

- [ ] **Step 2: Add route for WalletSettingsLive**

In `lib/nullzara_web/router.ex`, inside the authenticated scope with `pipe_through [:browser, :require_auth]`, add inside the existing `live_session :authenticated` block:

```elixir
live "/user/:id/settings/wallet", WalletSettingsLive
```

Note: This route goes inside `live_session :authenticated` (which has `on_mount: [{NullzaraWeb.Plugs.Auth, :require_authenticated_user}]`) so the `@current_user` assign is available.

- [ ] **Step 3: Create WalletSettingsLive tests**

Create `test/nullzara_web/live/wallet_settings_live_test.exs`:

```elixir
defmodule NullzaraWeb.WalletSettingsLiveTest do
  use NullzaraWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Nullzara.Users

  setup %{conn: conn} do
    {:ok, user} = Users.create_user_with_token(%{name: "Test"})
    conn = conn |> init_test_session(%{user_id: user.id})
    %{conn: conn, user: user}
  end

  describe "WalletSettingsLive" do
    test "renders the connect wallet page", %{conn: conn, user: user} do
      {:ok, _view, html} = live(conn, ~p"/user/#{user}/settings/wallet")

      assert html =~ "Connect Wallet"
      assert html =~ "Back to Settings"
    end

    test "connect_wallet sets loading state", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/user/#{user}/settings/wallet")

      assert view
             |> element("#wallet-attach-btn")
             |> render_click() =~ "Waiting for wallet"
    end

    test "wallet_error displays the error message", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/user/#{user}/settings/wallet")

      assert render_hook(view, "wallet_error", %{"message" => "No wallet detected"}) =~
               "No wallet detected"
    end
  end
end
```

- [ ] **Step 4: Verify compilation**

Run: `mix compile`
Expected: Compiles with no errors.

- [ ] **Step 5: Run all tests**

Run: `mix test`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/nullzara_web/live/wallet_settings_live.ex lib/nullzara_web/router.ex test/nullzara_web/live/wallet_settings_live_test.exs
git commit -m "Add WalletSettingsLive for attaching wallet from settings"
```

---

## Task 8: Final verification

- [ ] **Step 1: Run precommit**

Run: `mix precommit`
Expected: All checks pass (compile --warnings-as-errors, format, test).

- [ ] **Step 2: Fix any formatter issues**

If the formatter changed files, commit:

```bash
git add -A
git commit -m "Apply formatter fixes"
```

- [ ] **Step 3: Manual testing checklist**

Start: `iex -S mix phx.server`

1. Navigate to `http://localhost:4000`
2. Verify "Login with Wallet" button appears in navbar
3. Click it — should navigate to `/access/wallet`
4. If MetaMask is installed:
   - Click "Sign in with Wallet"
   - MetaMask should prompt to connect
   - Then prompt to sign a message
   - After signing, should redirect to dashboard with a new account
5. Log out, click "Login with Wallet" again, sign in with same wallet — should log into existing account
6. Go to Settings — should see "Wallet" section with the connected address
7. Click "Disconnect Wallet" — should remove it
8. Click "Connect Wallet" from settings — should link wallet to current account

---

## Notes

### EIP-191 personal_sign

MetaMask's `personal_sign` method signs a message with the prefix `"\x19Ethereum Signed Message:\n" <length>` before hashing. The server must reconstruct this prefix to verify.

### window.ethereum

All EIP-1193 compatible wallets inject `window.ethereum`. This includes MetaMask, Coinbase Wallet, Trust Wallet, Rabby, etc. No additional JS libraries are needed.

### Security

- Nonces are single-use and expire after 120 seconds
- Phoenix.Token with `"wallet_auth"` salt ensures tokens from other flows can't be reused
- Addresses are always lowercased before storage and comparison
- The LiveView process lifecycle scopes nonces per-tab/per-connection
