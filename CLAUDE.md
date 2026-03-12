# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Nullzara is a Phoenix 1.8.3 web application (Elixir ~> 1.15) using LiveView, Ecto/PostgreSQL, Tailwind CSS v4 with vendored daisyUI, and Bandit as the HTTP server. No npm/package.json — JS deps are vendored in `assets/vendor/` and esbuild/tailwind are managed via Mix.

## Common Commands

```bash
mix setup                  # Install deps, create/migrate DB, build assets
mix phx.server             # Start dev server at localhost:4000
iex -S mix phx.server      # Start with IEx shell

mix test                   # Run all tests (auto-creates/migrates DB)
mix test test/path_test.exs           # Run a single test file
mix test test/path_test.exs:42        # Run a specific test at line
mix test --failed                     # Re-run failed tests

mix format                 # Format Elixir/HEEx files
mix precommit              # compile --warnings-as-errors + deps.unlock --unused + format + test
```

**Always run `mix precommit` before finalizing changes** — it is the canonical pre-commit check.

### Database

```bash
mix ecto.gen.migration name_in_underscores   # Generate migration (never create manually)
mix ecto.migrate                              # Run pending migrations
mix ecto.reset                                # Drop + create + migrate + seed
```

## Architecture

- **Domain contexts** live in `lib/nullzara/` (e.g., `Nullzara.Accounts`)
- **Web layer** lives in `lib/nullzara_web/` — controllers, LiveViews, components
- **Shared UI components** are in `lib/nullzara_web/components/core_components.ex` — imported app-wide via `html_helpers/0` in `nullzara_web.ex`
- **Layouts** are in `lib/nullzara_web/components/layouts.ex` — `<Layouts.app>` wraps all LiveView templates
- **Router**: `lib/nullzara_web/router.ex` — the default `scope "/", NullzaraWeb` provides a module alias prefix, so routes within it should not repeat `NullzaraWeb`
- **Repo**: `Nullzara.Repo` (PostgreSQL)

### Dev-only routes

- `/dev/dashboard` — Phoenix LiveDashboard
- `/dev/mailbox` — Swoosh email preview

## Key Conventions (see AGENTS.md for full details)

Read `AGENTS.md` for comprehensive Phoenix 1.8, LiveView, Ecto, HEEx, and Elixir conventions. The most critical rules:

- **LiveView templates** must start with `<Layouts.app flash={@flash}>...</Layouts.app>`
- **Forms** must use `to_form/2` to create the form assign — never pass raw changesets to templates
- **Collections** must use LiveView streams (`stream/3`) — never assign plain lists
- **Icons** use `<.icon name="hero-*">` — never use Heroicons modules
- **HTTP client** is `Req` — never use HTTPoison, Tesla, or :httpc
- **Tailwind v4** has no `tailwind.config.js` — uses `@import`/`@source`/`@plugin` in `app.css`
- **No `@apply`** in CSS; no daisyUI prebuilt components — hand-craft with Tailwind utilities
- **No inline `<script>` tags** in HEEx — use colocated hooks (`:type={Phoenix.LiveView.ColocatedHook}`) with `.` prefixed names
- **HEEx interpolation**: `{@assign}` in attributes and values, `<%= ... %>` for block constructs only
- **Router scopes** provide module aliases — don't duplicate the prefix in route definitions
- **Ecto**: always preload associations before template access; use `:string` type (not `:text`); never put security-sensitive fields in `cast`
- **Tests**: use `start_supervised!/1` for processes, never `Process.sleep/1`; use `has_element?/2` and `element/2` for assertions, not raw HTML matching

## Production

Required env vars: `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`

```bash
mix assets.deploy                          # Minify + digest
PHX_SERVER=true bin/nullzara start      # After mix release
```
