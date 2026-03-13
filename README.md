# Nullzara

A privacy-first, boilerplate user authentication app built with Phoenix 1.8 and LiveView. Nullzara provides multiple passwordless authentication methods out of the box, designed to be integrated with your content applications.

No emails collected. No passwords stored. No tracking. Users authenticate through cryptographic tokens, hardware-backed passkeys, or blockchain wallets — and can remain fully anonymous.

## Features

### Multiple Authentication Methods

| Method | How it works |
|--------|-------------|
| **Anonymous Account** | One-click account creation. User receives a 12-word mnemonic recovery phrase and a rotatable login token. |
| **Mnemonic Login** | Sign in by entering your 12-word BIP39 recovery phrase. |
| **Token Login** | Sign in with a 32-character hex token. |
| **Passkey (WebAuthn)** | Sign in with biometrics (Face ID, Touch ID) or a hardware security key. Auto-creates an account on first use. |
| **Wallet (Ethereum)** | Sign in with MetaMask or any EIP-1193 compatible wallet. Signs a server-generated nonce via `personal_sign`. Auto-creates an account on first use. |
| **Magic Link** | Creates a token-only account accessible via a shareable URL. |

### Privacy-First Design

- **No passwords** — all methods use cryptographic tokens, signatures, or hardware-backed keys
- **No email required** — accounts are anonymous by default
- **Deterministic pseudonyms** — each user gets a friendly slug (e.g. "brave-tiger-explorer") derived from their auth credentials, so identities are recognizable without revealing personal information
- **Token rotation** — users can regenerate their login token at any time from settings
- **Wallet privacy** — Ethereum addresses are stored but never exposed in URLs
- **Time-limited nonces** — wallet and passkey challenges expire after 120 seconds
- **Rate limiting** — in-memory rate limiting per IP on account creation and verification

### Account Management

- Change display nickname from settings
- Attach or detach an Ethereum wallet
- Regenerate login token
- Delete account entirely
- Visual gradient identicon derived from wallet address bytes

## Integration

Nullzara is designed as a standalone authentication layer. To integrate with a content app:

1. Nullzara manages user creation, authentication, and session management
2. Your content app references `user_id` from the session to associate content with users
3. The `current_user` assign is available in all templates via the auth plug
4. Protected routes use the `:require_auth` plug (controllers) or `on_mount` callback (LiveView)

## Getting Started

### Requirements

- Elixir ~> 1.15
- PostgreSQL
- No Node.js required (JS deps are vendored, assets managed via Mix)

### Setup

```bash
mix setup                  # Install deps, create DB, run migrations, build assets
mix phx.server             # Start dev server at localhost:4000
```

Or start with an interactive shell:

```bash
iex -S mix phx.server
```

### Running Tests

```bash
mix test                             # Run all tests
mix test test/path_test.exs          # Run a single test file
mix test test/path_test.exs:42       # Run a specific test at a line
```

### Database

```bash
mix ecto.gen.migration name          # Generate a new migration
mix ecto.migrate                     # Run pending migrations
mix ecto.reset                       # Drop + create + migrate + seed
```

## Production

Set the following environment variables:

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | PostgreSQL connection string |
| `SECRET_KEY_BASE` | 64+ byte secret for signing sessions and tokens |
| `PHX_HOST` | Public hostname (e.g. `nullzara.example.com`) |

```bash
mix assets.deploy                    # Minify + digest static assets
PHX_SERVER=true bin/nullzara start   # Start the release
```

## Tech Stack

- **Phoenix** 1.8.3 with **LiveView** 1.1
- **Ecto** + **PostgreSQL**
- **Tailwind CSS v4** (no config file, uses `@import`/`@plugin` in `app.css`)
- **Bandit** HTTP server
- **wax_** for WebAuthn/FIDO2
- **ex_secp256k1** + **ex_keccak** for Ethereum signature verification
- Colocated LiveView JS hooks (no npm, no package.json)
