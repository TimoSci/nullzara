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

## Authentication Flow

### Login / Registration (`/access/wallet`)

1. User clicks "Sign in with Wallet" on WalletLive page.
2. JS hook checks `window.ethereum` availability. If absent, shows "No wallet detected" message.
3. JS hook calls `eth_requestAccounts` to connect wallet, gets address.
4. JS hook pushes `wallet_connected` event with the address to LiveView.
5. LiveView generates a random nonce, stores it in assigns, pushes `sign_message` event with the message `"Sign in to Nullzara\n\nNonce: <random_hex>"`.
6. JS hook calls `personal_sign` with the message, pushes `message_signed` event with signature back.
7. LiveView verifies: recovers address from signature + message using EC recover, checks it matches the claimed address.
8. On success:
   - Look up `wallet_credentials` by address.
   - **Found:** get associated user.
   - **Not found:** auto-create user via `User.registration_changeset` (gets mnemonic_hash + token_hash), create wallet credential.
   - Sign a Phoenix.Token with the user_id (60s expiry), redirect to `/access/wallet/complete`.
9. WalletController.complete verifies the token, sets `user_id` in session, redirects to dashboard.

### Attach Wallet (Settings page)

1. Settings page shows "Connect Wallet" button if no wallet attached.
2. Same sign-message flow as login, but instead of creating/finding a user, attaches the wallet credential to the current user.
3. If the address is already attached to another user, show an error.

### Detach Wallet (Settings page)

1. Settings page shows current wallet address and "Detach" button if wallet is attached.
2. Detach deletes the wallet_credential record.

## Module Structure

| Module | Responsibility |
|--------|---------------|
| `Nullzara.Wallet` | Context: nonce generation, signature verification (EC recover + keccak), credential CRUD |
| `Nullzara.Wallet.Credential` | Ecto schema for `wallet_credentials` |
| `NullzaraWeb.WalletLive` | LiveView at `/access/wallet` with colocated JS hook for `window.ethereum` |
| `NullzaraWeb.WalletController` | Completion controller (verifies Phoenix.Token, sets session) |

Settings page (`SettingsController` / settings template) gets a new wallet section for attach/detach.

## Signature Verification Details

EIP-191 `personal_sign` prefixes the message with `"\x19Ethereum Signed Message:\n" <length>` before hashing with keccak256. The verification process:

1. Reconstruct the prefixed message hash: `keccak256("\x19Ethereum Signed Message:\n" <> byte_size(message) <> message)`
2. Use `ex_secp256k1` EC recover to get the public key from the hash + signature (v, r, s components)
3. Derive the address: `"0x" <> last_20_bytes(keccak256(public_key))`
4. Compare (case-insensitive) with the claimed address

## Dependencies

- `{:ex_secp256k1, "~> 0.7"}` — NIF wrapper for libsecp256k1, provides EC recovery
- `{:ex_keccak, "~> 0.7"}` — NIF wrapper for keccak256 hashing

No client-side JS libraries needed — `window.ethereum` is injected by the wallet extension and provides the full EIP-1193 API.

## Testing Strategy

- **`Nullzara.WalletTest`** — context unit tests: generate a known keypair, sign a message, verify address recovery; credential CRUD (store, get_by_address, detach)
- **`NullzaraWeb.WalletLiveTest`** — LiveView rendering, button interactions, error event handling
- **`NullzaraWeb.WalletControllerTest`** — valid/invalid Phoenix.Token verification, session setting
- Settings wallet section tested in existing settings tests
- Full MetaMask flow requires manual browser testing
