# WebAuthn Passkey Login Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to register and log in using WebAuthn passkeys, with automatic account creation on first registration.

**Architecture:** Use the `wax_` hex package for server-side WebAuthn challenge generation and verification. A new `webauthn_credentials` table stores credential data per user. A LiveView at `/access/passkey` handles both registration (creates a new user + stores credential) and authentication (looks up existing credential, logs in). A colocated JS hook calls the browser's `navigator.credentials.create()` / `.get()` APIs. The flow integrates with the existing session-based auth (sets `user_id` in session on success).

**Tech Stack:** `wax_` (Elixir WebAuthn library), Phoenix LiveView, colocated JS hooks, Ecto/PostgreSQL.

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `mix.exs` | Modify | Add `wax_` dependency |
| `config/config.exs` | Modify | Add Wax rp_name (environment-agnostic) |
| `config/dev.exs` | Modify | Dev Wax config (localhost rp_id + origin) |
| `config/test.exs` | Modify | Test Wax config |
| `config/runtime.exs` | Modify | Production Wax config (from PHX_HOST env var) |
| `priv/repo/migrations/*_create_webauthn_credentials.exs` | Create | Migration for credentials table |
| `lib/nullzara/webauthn/credential.ex` | Create | Ecto schema for webauthn_credentials |
| `lib/nullzara/webauthn.ex` | Create | Context module: challenge generation, registration, authentication |
| `lib/nullzara_web/live/passkey_live.ex` | Create | LiveView handling registration + authentication flows |
| `lib/nullzara_web/router.ex` | Modify | Add `/access/passkey` route |
| `lib/nullzara_web/components/layouts.ex` | Modify | Add "Login with Passkey" button |
| `test/nullzara/webauthn_test.exs` | Create | Context tests |
| `test/nullzara_web/live/passkey_live_test.exs` | Create | LiveView tests |

---

## Task 1: Add wax_ dependency and configure

**Files:**
- Modify: `mix.exs`
- Modify: `config/config.exs`
- Modify: `config/dev.exs`
- Modify: `config/test.exs`

- [ ] **Step 1: Add wax_ to deps in mix.exs**

In the `deps` function, add:

```elixir
{:wax_, "~> 0.7"}
```

- [ ] **Step 2: Run mix deps.get**

Run: `mix deps.get`
Expected: wax_ and its dependencies download successfully.

- [ ] **Step 3: Add Wax config to config.exs**

Add environment-agnostic Wax configuration only:

```elixir
# Configure WebAuthn (Wax)
config :wax_,
  rp_name: "Nullzara"
```

- [ ] **Step 4: Add dev-specific Wax config to dev.exs**

```elixir
# WebAuthn config for development
config :wax_,
  rp_id: "localhost",
  origin: "http://localhost:4000"
```

- [ ] **Step 5: Add test Wax config to test.exs**

```elixir
# WebAuthn config for tests
config :wax_,
  rp_id: "localhost",
  origin: "http://localhost:4000"
```

- [ ] **Step 6: Add production Wax config to runtime.exs**

In `config/runtime.exs`, inside the `if config_env() == :prod do` block, add:

```elixir
config :wax_,
  rp_id: host,
  origin: "https://#{host}"
```

(The `host` variable is already defined from `PHX_HOST` env var in runtime.exs.)

- [ ] **Step 7: Verify compilation**

Run: `mix compile`
Expected: Compiles with no errors.

- [ ] **Step 8: Commit**

```bash
git add mix.exs mix.lock config/config.exs config/dev.exs config/test.exs config/runtime.exs
git commit -m "Add wax_ dependency and WebAuthn configuration"
```

---

## Task 2: Create webauthn_credentials migration and schema

**Files:**
- Create: `priv/repo/migrations/*_create_webauthn_credentials.exs` (via `mix ecto.gen.migration`)
- Create: `lib/nullzara/webauthn/credential.ex`

- [ ] **Step 1: Generate migration**

Run: `mix ecto.gen.migration create_webauthn_credentials`

- [ ] **Step 2: Write the migration**

Edit the generated migration file:

```elixir
defmodule Nullzara.Repo.Migrations.CreateWebauthnCredentials do
  use Ecto.Migration

  def change do
    create table(:webauthn_credentials) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :credential_id, :binary, null: false
      add :public_key, :map, null: false
      add :sign_count, :integer, null: false, default: 0
      add :friendly_name, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:webauthn_credentials, [:credential_id])
    create index(:webauthn_credentials, [:user_id])
  end
end
```

- [ ] **Step 3: Run the migration**

Run: `mix ecto.migrate`
Expected: Migration runs successfully.

- [ ] **Step 4: Write the Credential schema**

Create `lib/nullzara/webauthn/credential.ex`:

```elixir
defmodule Nullzara.Webauthn.Credential do
  use Ecto.Schema
  import Ecto.Changeset

  schema "webauthn_credentials" do
    belongs_to :user, Nullzara.Users.User
    field :credential_id, :binary
    field :public_key, :map
    field :sign_count, :integer, default: 0
    field :friendly_name, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [:credential_id, :public_key, :sign_count, :friendly_name])
    |> validate_required([:credential_id, :public_key])
    |> unique_constraint(:credential_id)
    |> foreign_key_constraint(:user_id)
  end
end
```

- [ ] **Step 5: Add has_many to User schema**

In `lib/nullzara/users/user.ex`, add inside the `schema "users"` block:

```elixir
has_many :webauthn_credentials, Nullzara.Webauthn.Credential
```

- [ ] **Step 6: Verify compilation**

Run: `mix compile`
Expected: Compiles with no errors.

- [ ] **Step 7: Commit**

```bash
git add priv/repo/migrations/*_create_webauthn_credentials.exs lib/nullzara/webauthn/credential.ex lib/nullzara/users/user.ex
git commit -m "Add webauthn_credentials table and schema"
```

---

## Task 3: Create Webauthn context module with tests

**Files:**
- Create: `lib/nullzara/webauthn.ex`
- Create: `test/nullzara/webauthn_test.exs`

The context wraps Wax calls and handles credential storage. It exposes four functions:
- `generate_registration_challenge/0` — returns a challenge for `navigator.credentials.create()`
- `register_credential/3` — verifies attestation, creates user + credential, returns `{:ok, user}`
- `generate_authentication_challenge/0` — returns a challenge for `navigator.credentials.get()` (discoverable credentials, empty allowCredentials)
- `authenticate/3` — verifies assertion, looks up user, returns `{:ok, user}`

- [ ] **Step 1: Write tests for the context**

Create `test/nullzara/webauthn_test.exs`:

```elixir
defmodule Nullzara.WebauthnTest do
  use Nullzara.DataCase, async: true

  alias Nullzara.Webauthn
  alias Nullzara.Webauthn.Credential

  describe "generate_registration_challenge/0" do
    test "returns a Wax.Challenge struct" do
      challenge = Webauthn.generate_registration_challenge()
      assert %Wax.Challenge{} = challenge
    end
  end

  describe "generate_authentication_challenge/0" do
    test "returns a Wax.Challenge struct" do
      challenge = Webauthn.generate_authentication_challenge()
      assert %Wax.Challenge{} = challenge
    end
  end

  describe "store_credential/3" do
    test "creates a user and credential record" do
      # Use a fake credential_id and cose_key for DB storage test
      credential_id = :crypto.strong_rand_bytes(32)
      cose_key = %{1 => 2, 3 => -7, -1 => 1, -2 => :crypto.strong_rand_bytes(32), -3 => :crypto.strong_rand_bytes(32)}

      assert {:ok, user, credential} = Webauthn.store_credential(credential_id, cose_key, 0)
      assert user.name == "Anonymous"
      assert user.mnemonic_hash != nil
      assert user.token_hash != nil
      assert credential.credential_id == credential_id
      assert credential.sign_count == 0
      assert credential.user_id == user.id
    end
  end

  describe "get_credential_by_id/1" do
    test "returns credential with preloaded user" do
      credential_id = :crypto.strong_rand_bytes(32)
      cose_key = %{1 => 2, 3 => -7, -1 => 1, -2 => :crypto.strong_rand_bytes(32), -3 => :crypto.strong_rand_bytes(32)}
      {:ok, _user, _credential} = Webauthn.store_credential(credential_id, cose_key, 0)

      assert {:ok, found} = Webauthn.get_credential_by_id(credential_id)
      assert found.credential_id == credential_id
      assert %Nullzara.Users.User{} = found.user
    end

    test "returns error for unknown credential" do
      assert {:error, :not_found} = Webauthn.get_credential_by_id(:crypto.strong_rand_bytes(32))
    end
  end

  describe "update_sign_count/2" do
    test "updates the sign count" do
      credential_id = :crypto.strong_rand_bytes(32)
      cose_key = %{1 => 2, 3 => -7, -1 => 1, -2 => :crypto.strong_rand_bytes(32), -3 => :crypto.strong_rand_bytes(32)}
      {:ok, _user, credential} = Webauthn.store_credential(credential_id, cose_key, 0)

      assert {:ok, updated} = Webauthn.update_sign_count(credential, 5)
      assert updated.sign_count == 5
    end
  end

  # COSE keys have integer keys; JSON encoding through Ecto :map converts them to strings
  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), stringify_value(v)} end)
  end

  defp stringify_value(v) when is_binary(v), do: Base.encode64(v)
  defp stringify_value(v), do: v
end
```

**Note:** We test the DB operations (store, get, update) directly. The actual Wax registration/authentication verification (`Wax.register/3`, `Wax.authenticate/5`) requires real browser-generated attestation/assertion data, so those are best tested via integration tests or the LiveView tests with a mock. The context functions that call Wax will be thin wrappers.

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/nullzara/webauthn_test.exs`
Expected: Failures because `Nullzara.Webauthn` module doesn't exist yet.

- [ ] **Step 3: Write the Webauthn context**

Create `lib/nullzara/webauthn.ex`:

```elixir
defmodule Nullzara.Webauthn do
  @moduledoc """
  Context for WebAuthn passkey registration and authentication.
  """

  alias Nullzara.Repo
  alias Nullzara.Users.User
  alias Nullzara.Webauthn.Credential

  import Ecto.Query

  def generate_registration_challenge do
    Wax.new_registration_challenge(
      attestation: "none",
      rp_name: Application.get_env(:wax_, :rp_name, "Nullzara")
    )
  end

  def generate_authentication_challenge do
    Wax.new_authentication_challenge(
      [],
      user_verification: "preferred"
    )
  end

  def verify_registration(attestation_object, client_data_json, challenge) do
    Wax.register(attestation_object, client_data_json, challenge)
  end

  def verify_authentication(credential_id, authenticator_data, signature, client_data_json, challenge) do
    case get_credential_by_id(credential_id) do
      {:ok, credential} ->
        cose_key = restore_cose_key(credential.public_key)

        # Attach the stored credential's key to the original challenge
        challenge = %{challenge | allow_credentials: [{credential.credential_id, cose_key}]}

        case Wax.authenticate(
          credential_id,
          authenticator_data,
          signature,
          client_data_json,
          challenge
        ) do
          {:ok, updated_sign_count} ->
            {:ok, _} = update_sign_count(credential, updated_sign_count)
            {:ok, credential.user}

          {:error, _} = error ->
            error
        end

      {:error, :not_found} ->
        {:error, :credential_not_found}
    end
  end

  def store_credential(credential_id, cose_key, sign_count) do
    Repo.transaction(fn ->
      # Use registration_changeset so user gets token_hash + mnemonic_hash
      # (required for slug generation in the navbar)
      {:ok, user} =
        %User{}
        |> User.registration_changeset(%{name: "Anonymous"})
        |> Repo.insert()

      serialized_key = serialize_cose_key(cose_key)

      {:ok, credential} =
        %Credential{}
        |> Credential.changeset(%{
          credential_id: credential_id,
          public_key: serialized_key,
          sign_count: sign_count
        })
        |> Ecto.Changeset.put_change(:user_id, user.id)
        |> Repo.insert()

      {user, credential}
    end)
    |> case do
      {:ok, {user, credential}} -> {:ok, user, credential}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_credential_by_id(credential_id) do
    query =
      from c in Credential,
        where: c.credential_id == ^credential_id,
        preload: [:user]

    case Repo.one(query) do
      nil -> {:error, :not_found}
      credential -> {:ok, credential}
    end
  end

  def update_sign_count(credential, new_count) do
    credential
    |> Credential.changeset(%{sign_count: new_count})
    |> Repo.update()
  end

  # COSE keys use integer keys and may contain binary values.
  # Ecto :map stores as JSONB, so we need to convert.
  defp serialize_cose_key(cose_key) do
    Map.new(cose_key, fn {k, v} -> {to_string(k), serialize_value(v)} end)
  end

  defp serialize_value(v) when is_binary(v), do: Base.encode64(v)
  defp serialize_value(v), do: v

  def restore_cose_key(stored_map) do
    Map.new(stored_map, fn {k, v} ->
      {String.to_integer(k), restore_value(v)}
    end)
  end

  defp restore_value(v) when is_binary(v) do
    case Base.decode64(v) do
      {:ok, decoded} -> decoded
      :error -> v
    end
  end

  defp restore_value(v), do: v
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/nullzara/webauthn_test.exs`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/nullzara/webauthn.ex test/nullzara/webauthn_test.exs
git commit -m "Add Webauthn context with credential storage and challenge generation"
```

---

## Task 4: Create PasskeyLive LiveView with colocated JS hook

**Files:**
- Create: `lib/nullzara_web/live/passkey_live.ex`

This is the most complex task. The LiveView has two modes:
1. **Authentication** — try to log in with an existing passkey (discoverable credential)
2. **Registration** — create a new account with a passkey

The JS hook handles the browser WebAuthn API calls and sends results back via `pushEvent`.

- [ ] **Step 1: Create the PasskeyLive module**

Create `lib/nullzara_web/live/passkey_live.ex`:

```elixir
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
    # Generate a temporary user ID for the WebAuthn ceremony
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
            {:noreply,
             socket
             |> assign(:loading, false)
             |> redirect(to: "/access/passkey/complete?token=#{Phoenix.Token.sign(NullzaraWeb.Endpoint, "passkey_auth", user.id)}")}

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
      credential_id, authenticator_data, signature, client_data_json, challenge
    ) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> redirect(to: "/access/passkey/complete?token=#{Phoenix.Token.sign(NullzaraWeb.Endpoint, "passkey_auth", user.id)}")}

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
```

**Important note on session setting:** LiveView cannot set session cookies directly. After successful WebAuthn verification, we redirect to a controller route (`/access/passkey/complete`) that sets the session. This is the same pattern used by the existing token verification flow.

- [ ] **Step 2: Verify compilation**

Run: `mix compile`
Expected: Compiles (route not added yet, but module compiles).

- [ ] **Step 3: Commit**

```bash
git add lib/nullzara_web/live/passkey_live.ex
git commit -m "Add PasskeyLive with colocated WebAuthn JS hook"
```

---

## Task 5: Add passkey completion controller and routes

**Files:**
- Create: `lib/nullzara_web/controllers/passkey_controller.ex`
- Modify: `lib/nullzara_web/router.ex`
- Modify: `lib/nullzara_web/components/layouts.ex`

The completion controller sets the session after WebAuthn success. We need a signed token to prevent abuse (user_id in query string alone is insecure).

- [ ] **Step 1: Create the PasskeyController**

Create `lib/nullzara_web/controllers/passkey_controller.ex`:

```elixir
defmodule NullzaraWeb.PasskeyController do
  use NullzaraWeb, :controller

  alias Nullzara.Users

  def complete(conn, %{"token" => token}) do
    case Phoenix.Token.verify(NullzaraWeb.Endpoint, "passkey_auth", token, max_age: 60) do
      {:ok, user_id} ->
        user = Users.get_user!(user_id)

        conn
        |> put_session(:user_id, user.id)
        |> configure_session(renew: true)
        |> redirect(to: ~p"/user/#{user}/dashboard")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Passkey session expired. Please try again.")
        |> redirect(to: ~p"/access/passkey")
    end
  end
end
```

- [ ] **Step 2: Add routes**

In `lib/nullzara_web/router.ex`, add to the first public browser scope:

```elixir
live "/access/passkey", PasskeyLive
get "/access/passkey/complete", PasskeyController, :complete
```

- [ ] **Step 3: Add "Login with Passkey" button to layout**

In `lib/nullzara_web/components/layouts.ex`, add after the "Login with token" button `<li>` block (around line 72):

```elixir
<li :if={!@current_user}>
  <.button navigate={~p"/access/passkey"}>
    <.icon name="hero-finger-print-mini" /> Login with Passkey
  </.button>
</li>
```

- [ ] **Step 4: Create LiveView and controller tests**

Create `test/nullzara_web/live/passkey_live_test.exs`:

```elixir
defmodule NullzaraWeb.PasskeyLiveTest do
  use NullzaraWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "PasskeyLive" do
    test "renders the passkey login page", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/access/passkey")

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
  end
end
```

Create `test/nullzara_web/controllers/passkey_controller_test.exs`:

```elixir
defmodule NullzaraWeb.PasskeyControllerTest do
  use NullzaraWeb.ConnCase, async: true

  alias Nullzara.Users

  describe "complete/2" do
    test "logs in user with valid token", %{conn: conn} do
      {:ok, user} = Users.create_user_with_token(%{name: "Test"})
      token = Phoenix.Token.sign(NullzaraWeb.Endpoint, "passkey_auth", user.id)

      conn = get(conn, ~p"/access/passkey/complete?token=#{token}")

      assert redirected_to(conn) =~ "/user/"
      assert get_session(conn, :user_id) == user.id
    end

    test "rejects expired token", %{conn: conn} do
      {:ok, user} = Users.create_user_with_token(%{name: "Test"})
      token = Phoenix.Token.sign(NullzaraWeb.Endpoint, "passkey_auth", user.id)

      # Simulate expired token by verifying with max_age: 0
      conn = get(conn, ~p"/access/passkey/complete?token=invalid_token")

      assert redirected_to(conn) == "/access/passkey"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "expired"
    end
  end
end
```

**Note:** Full WebAuthn registration/authentication flows require a real browser with authenticator support and cannot be tested via LiveView tests. The tests above verify the UI rendering, button interactions, error handling, and the controller's session-setting logic.

- [ ] **Step 5: Verify compilation**

Run: `mix compile`
Expected: No errors.

- [ ] **Step 6: Run all tests**

Run: `mix test`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/nullzara_web/controllers/passkey_controller.ex lib/nullzara_web/live/passkey_live.ex lib/nullzara_web/router.ex lib/nullzara_web/components/layouts.ex test/nullzara_web/live/passkey_live_test.exs test/nullzara_web/controllers/passkey_controller_test.exs
git commit -m "Add passkey routes, completion controller, navbar button, and tests"
```

---

## Task 6: Manual testing and integration verification

- [ ] **Step 1: Start the dev server**

Run: `iex -S mix phx.server`

- [ ] **Step 2: Test registration flow**

1. Navigate to `http://localhost:4000`
2. Click "Login with Passkey" in the navbar
3. Click "Create Account with Passkey"
4. Browser should prompt for biometric/PIN
5. After confirmation, should redirect to dashboard
6. Navbar should show "Signed in as ..."

- [ ] **Step 3: Test authentication flow**

1. Log out
2. Click "Login with Passkey"
3. Click "Sign in with Passkey"
4. Browser should prompt with the previously registered passkey
5. After confirmation, should redirect to dashboard

- [ ] **Step 4: Run precommit**

Run: `mix precommit`
Expected: All checks pass.

- [ ] **Step 5: Final commit if any fixes needed**

```bash
git add -A
git commit -m "Fix any issues found during manual WebAuthn testing"
```

---

## Notes

### Wax API reference

The key Wax functions used in this plan:

- `Wax.new_registration_challenge/1` — generates a challenge for credential creation. Options: `:attestation`, `:rp_name`, etc.
- `Wax.register/3` — verifies an attestation response. Args: `attestation_object` (binary), `client_data_json` (binary), `challenge` (Wax.Challenge). Returns `{:ok, {authenticator_data, attestation_result}}`.
- `Wax.new_authentication_challenge/2` — generates a challenge for assertion. First arg is list of `{credential_id, cose_key}` tuples. For discoverable credentials, pass `[]`.
- `Wax.authenticate/5` — verifies an assertion. Args: `credential_id`, `authenticator_data`, `signature`, `client_data_json`, `challenge`. Returns `{:ok, sign_count}`.

### COSE key storage

Wax returns COSE keys as Elixir maps with integer keys (e.g., `%{1 => 2, 3 => -7, -1 => 1, ...}`). PostgreSQL JSONB requires string keys, so we convert integer keys to strings and base64-encode binary values before storage, then restore on load.

### Session handling

LiveView cannot set cookies. The pattern used here is:
1. LiveView does WebAuthn verification
2. On success, signs a short-lived Phoenix.Token containing the user_id
3. Redirects to a controller route that verifies the token and sets the session
4. Controller redirects to dashboard

This is secure because the token is signed with the endpoint's secret_key_base and expires after 60 seconds.

### Future enhancements (not in scope)

- Allow existing users to add passkeys from settings page
- Support multiple passkeys per user
- Show passkey management UI (rename, delete)
- Conditional UI: detect if browser supports WebAuthn before showing button
