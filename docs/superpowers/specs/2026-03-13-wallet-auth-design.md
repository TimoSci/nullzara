# Wallet Authentication Design

## Goal

Allow users to sign in or create accounts using an Ethereum wallet (MetaMask and any EIP-1193 compatible wallet). Wallet addresses are attachable/detachable credentials — a user can sign in with only a wallet, or attach one to an existing account.

## Architecture

Server-side signature verification using the standard "sign a message" pattern. No blockchain interaction required. The server generates a nonce, the wallet signs it, and the server recovers the Ethereum address from the signature using `ex_secp256k1` + `ex_keccak`. This works with any wallet that supports `personal_sign` (EIP-191), which includes MetaMask, Coinbase Wallet, Trust Wallet, Rabby, etc.

## Data Model

New `wallet_credentials` table:

| Column     | Type       | Constraints                              |
|------------|------------|------------------------------------------|
| id         | bigint     | PK                                       |
| user_id    | references | NOT NULL, on_delete: delete_all, unique   |
| address    | string     | NOT NULL, unique (0x-prefixed, lowercase) |
| inserted_at| utc_datetime |                                         |
| updated_at | utc_datetime |                                         |

One wallet per user (unique index on `user_id`). Unique index on `address` ensures no two users share a wallet.

Add `has_one :wallet_credential, Nullzara.Wallet.Credential` to the User schema.

## Authentication Flow

### Login / Registration (`/access/wallet`)

1. User clicks "Sign in with Wallet" on WalletLive page.
2. JS hook checks `window.ethereum` availability. If absent, shows "No wallet detected. Install MetaMask or another Ethereum wallet."
3. JS hook calls `eth_requestAccounts` to connect wallet, gets address.
4. JS hook pushes `wallet_connected` event with the address to LiveView.
5. LiveView generates a random nonce (32 random bytes, hex-encoded), stores it in assigns along with a timestamp. Pushes `sign_message` event with the message `"Sign in to Nullzara\n\nNonce: <random_hex>"`.
6. JS hook calls `personal_sign` with the message, pushes `message_signed` event with signature back.
7. LiveView verifies:
   - Check nonce is not older than 120 seconds (reject if expired).
   - Recover address from signature + message using EC recover.
   - Downcase both recovered and claimed addresses before comparison.
   - Clear the nonce from assigns after verification (single-use).
8. On success:
   - Look up `wallet_credentials` by address.
   - **Found:** get associated user.
   - **Not found:** auto-create user via `User.registration_changeset(%{name: "Anonymous"})` (gets mnemonic_hash + token_hash), create wallet credential.
   - Sign a Phoenix.Token with salt `"wallet_auth"` and user_id (60s expiry), redirect to `/access/wallet/complete`.
9. WalletController.complete verifies the token (salt `"wallet_auth"`, max_age 60), sets `user_id` in session, redirects to dashboard.

Note: Each LiveView process has its own nonce in assigns, so multiple tabs work independently. The nonce is scoped to the process lifecycle.

### Attach Wallet (Settings page)

The settings page is a controller-rendered page, not a LiveView. Wallet attachment requires JS interaction (wallet signing). To handle this, a separate LiveView route at `/user/:id/settings/wallet` handles the attach flow:

1. Settings page shows "Connect Wallet" button (links to `/user/:id/settings/wallet`) if no wallet attached.
2. The wallet settings LiveView runs the same sign-message flow as login, but attaches the wallet credential to the current authenticated user instead of creating one.
3. If the address is already attached to another user, show an error.
4. On success, redirects back to the settings page.

### Detach Wallet (Settings page)

1. Settings page shows current wallet address and "Detach" button if wallet is attached.
2. Detach is a POST/DELETE to the settings controller which deletes the wallet_credential record.
3. Since wallet-created users also have mnemonic + token credentials (from `registration_changeset`), they retain access after detaching. The settings page should display the user's recovery phrase / token information so the user is aware of their backup credentials.

## Module Structure

| Module | Responsibility |
|--------|---------------|
| `Nullzara.Wallet` | Context: nonce generation, signature verification (EC recover + keccak), credential CRUD |
| `Nullzara.Wallet.Credential` | Ecto schema for `wallet_credentials` |
| `NullzaraWeb.WalletLive` | LiveView at `/access/wallet` with colocated JS hook for `window.ethereum` |
| `NullzaraWeb.WalletController` | Completion controller (verifies Phoenix.Token, sets session) |
| `NullzaraWeb.WalletSettingsLive` | LiveView at `/user/:id/settings/wallet` for attaching wallet to existing account |

## Signature Verification Details

EIP-191 `personal_sign` prefixes the message with `"\x19Ethereum Signed Message:\n"` followed by the string representation of the byte length before hashing with keccak256. The message is always ASCII. The verification process:

1. Reconstruct the prefixed message hash: `keccak256("\x19Ethereum Signed Message:\n" <> Integer.to_string(byte_size(message)) <> message)`
2. Parse the 65-byte signature into r (32 bytes), s (32 bytes), v (1 byte). Normalize v: if `v >= 27`, subtract 27 (Ethereum uses 27/28, `ex_secp256k1` expects 0/1).
3. Use `ExSecp256k1.recover(hash, signature_rs, recovery_id)` to get the 65-byte public key.
4. Derive the address: `"0x" <> last_20_bytes(keccak256(uncompressed_pubkey_without_prefix))`, lowercased.
5. Downcase both recovered and claimed addresses, then compare for equality.

## Rate Limiting

The `/access/wallet` LiveView route does not need a rate-limiting plug — the LiveView process lifecycle provides natural throttling (one connection = one process, nonces are per-process). The `/access/wallet/complete` GET endpoint uses the same `rate_limit_verify` pipeline as token verification.

## Dependencies

- `{:ex_secp256k1, "~> 0.7"}` — NIF wrapper for libsecp256k1, provides EC recovery
- `{:ex_keccak, "~> 0.7"}` — NIF wrapper for keccak256 hashing

No client-side JS libraries needed — `window.ethereum` is injected by the wallet extension and provides the full EIP-1193 API.

## Testing Strategy

- **`Nullzara.WalletTest`** — context unit tests: generate a known keypair with `ex_secp256k1`, sign a message, verify address recovery returns the correct address; nonce expiry; credential CRUD (store, get_by_address, detach)
- **`NullzaraWeb.WalletLiveTest`** — LiveView rendering, button interactions, error event handling
- **`NullzaraWeb.WalletControllerTest`** — valid/invalid/expired Phoenix.Token verification, session setting
- **`NullzaraWeb.WalletSettingsLiveTest`** — wallet attach flow for authenticated users
- Full MetaMask flow requires manual browser testing
