# E2E Bug Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix bugs 2–10 and the smaller issues found in the 2026-11-13 browser test pass of Nullzara (bug 1, `/users` authorization, is already fixed in `9bc925f`).

**Architecture:** Each task is one bug or one group of bugs sharing a file, with its own failing test first. Input normalisation and validation go in the context/schema layer (`Mnemonic`, `User`, `Wallet`); routing and session fixes go in controllers, the `Auth` plug and the router; the navbar and flash fixes are template-only and are checked in a browser.

**Tech Stack:** Phoenix 1.8.3, LiveView, Ecto/PostgreSQL, Tailwind v4 + vendored daisyUI, ExUnit with `Phoenix.LiveViewTest`.

**Spec:** There is no separate spec. The bug statements below are the requirements; each task restates its bug.

## Global Constraints

- Run `mix precommit` before every commit; it must pass with no warnings.
- LiveView tests use `has_element?/2` / `element/2` or redirect tuples, never `Process.sleep/1`.
- Never add security-sensitive fields to `cast`.
- HEEx: no inline `<script>`, `{@assign}` interpolation, `<.icon>` for icons.
- Do not change the dev admin config or `ADMIN_UUIDS` behaviour.
- One commit per task. Do not push.

## Decisions made in this plan (review these first)

1. **Nickname limit is 50 characters** (bug 2). The column allows 255; 50 is chosen so the navbar stays readable.
2. **`/users/<magic-link token>` becomes a redirect to `/u/<token>`**, which logs in (bug 5). Links people already saved keep working, and the user record page becomes admin-only.
3. **A magic-link account's slug is seeded from its UUID, not its token hash** (bug 6), so regenerating the token no longer changes the displayed identity. Existing magic-link accounts get a different slug once, when this ships.
4. **A `/user/:id/...` address whose `:id` is not the signed-in account redirects to that account's own dashboard** (minor issue), instead of silently showing the session user's page.
5. **Flash messages move to the bottom-right corner** (bug 9).

## Review Focus

Inputs no bug report covers but a user will hit; each has a test in the owning task:

1. Recovery phrase with mixed case *and* extra whitespace or newlines between words → logs in (Task 2).
2. Nickname of exactly 50 characters, and one of 50 multi-byte characters (e.g. emoji) → accepted (Task 1).
3. Wallet signature that is valid hex but the wrong length, has no `0x` prefix, or is not a string → error message, LiveView stays alive (Task 3).
4. Magic-link user regenerates the token twice in a row → still signed in, every navbar link works (Task 5).
5. Signed-in admin opens `/users/<someone's magic-link token>` → sees the record, is not logged in as that user (Task 4).

---

### Task 1: Nickname length validation (bug 2)

**Bug:** A nickname over 255 characters returns a 500 (`value too long for type character varying(255)`) from settings and from the `/users` forms.

**Files:**
- Modify: `lib/nullzara/users/user.ex` (`changeset/2`)
- Test: `test/nullzara/users_test.exs`, `test/nullzara_web/controllers/settings_controller_test.exs`

- [ ] **Step 1: Write failing tests**

```elixir
# users_test.exs
test "update_user/2 rejects a name longer than 50 characters" do
  user = user_fixture()
  assert {:error, changeset} = Users.update_user(user, %{name: String.duplicate("a", 51)})
  assert "should be at most 50 character(s)" in errors_on(changeset).name
end

test "update_user/2 accepts 50 characters, including multi-byte ones" do
  user = user_fixture()
  assert {:ok, _} = Users.update_user(user, %{name: String.duplicate("a", 50)})
  assert {:ok, _} = Users.update_user(user, %{name: String.duplicate("🙂", 50)})
end

# settings_controller_test.exs — signed-in conn
test "a too-long nickname re-renders the form with an error", %{conn: conn, user: user} do
  conn = put(conn, ~p"/user/#{user}/settings", user: %{name: String.duplicate("a", 300)})
  assert html_response(conn, 200) =~ "should be at most 50 character(s)"
end
```

- [ ] **Step 2: Run** `mix test test/nullzara/users_test.exs test/nullzara_web/controllers/settings_controller_test.exs` — expect the new tests to fail (the controller one with `Postgrex.Error`).
- [ ] **Step 3: Add** `validate_length(:name, max: 50)` to `User.changeset/2`. If the settings template does not already show field errors, render the form through `<.input field={...}>` so it does.
- [ ] **Step 4: Run** the same command — expect pass.
- [ ] **Step 5: Commit** `Limit nicknames to 50 characters`.

### Task 2: Case-insensitive tokens and recovery phrases (bugs 3, 4)

**Bugs:** A correct token typed in capitals is rejected and counted as a failed attempt. Capitalised recovery words are "not recognized".

**Files:**
- Modify: `lib/nullzara_web/controllers/token_controller.ex` (`verify/2`), `lib/nullzara/users/mnemonic.ex` (`decode_words/1`)
- Test: `test/nullzara_web/controllers/token_controller_test.exs`, `test/nullzara/users/mnemonic_test.exs`, `test/nullzara_web/live/access_live_test.exs`

- [ ] **Step 1: Write failing tests**

```elixir
# token_controller_test.exs
test "GET /u/:token accepts the token in upper case", %{conn: conn} do
  {user, _token, login_token} = user_fixture_with_token()
  conn = get(conn, ~p"/u/#{String.upcase(login_token)}")
  assert redirected_to(conn) == ~p"/user/#{user}/dashboard"
end

# mnemonic_test.exs
test "decode/1 ignores case and extra whitespace" do
  token = "00112233445566778899aabbccddeeff"
  messy = token |> Mnemonic.encode() |> String.upcase() |> String.replace(" ", " \n  ")
  assert Mnemonic.decode(messy) == {:ok, token}
end
```

Add an `access_live_test.exs` case submitting a capitalised phrase and asserting the redirect goes to `/u/<lower-case token>`.

- [ ] **Step 2: Run** the three files — expect the new tests to fail.
- [ ] **Step 3: Implement.** In `TokenController.verify/2`, lower-case `raw_token` on entry so the lookup *and* the value stored in the session are lower-case. In `Mnemonic.decode_words/1`, lower-case each word before lookup.
- [ ] **Step 4: Run** — expect pass.
- [ ] **Step 5: Commit** `Accept tokens and recovery phrases in any letter case`.

### Task 3: Malformed wallet signature must not crash (bug 10)

**Bug:** A signature that is not 65 bytes of hex raises (`Base.decode16!` / `MatchError` in `Wallet.recover_address/2`), killing the LiveView.

**Files:**
- Modify: `lib/nullzara/wallet.ex` (`verify_signature/3`, `recover_address/2`)
- Test: `test/nullzara/wallet_test.exs`, `test/nullzara_web/live/wallet_live_test.exs`, `test/nullzara_web/live/wallet_settings_live_test.exs`

**Interfaces:**
- Produces: `Wallet.verify_signature(signature :: term, message, address)` returns `{:ok, address} | {:error, :invalid_signature | :address_mismatch | term}` and never raises.

- [ ] **Step 1: Write failing tests**

```elixir
# wallet_test.exs
for {label, sig} <- [
      {"not hex", "0xzz"},
      {"too short", "0x" <> String.duplicate("ab", 64)},
      {"too long", "0x" <> String.duplicate("ab", 66)},
      {"empty", ""},
      {"not a string", nil}
    ] do
  test "verify_signature/3 returns an error for a signature that is #{label}" do
    assert {:error, :invalid_signature} =
             Wallet.verify_signature(unquote(sig), "msg", "0x" <> String.duplicate("0", 40))
  end
end

test "verify_signature/3 accepts a valid signature without the 0x prefix" do
  # reuse the existing valid-signature fixture in this file, with "0x" stripped
end
```

In both LiveView test files: reach the signing step the way the existing tests do, `render_hook(view, "message_signed", %{"signature" => "0xzz"})`, then assert an error element is shown and `Process.alive?(view.pid)`.

- [ ] **Step 2: Run** the three files — expect failures with `ArgumentError`/`MatchError`.
- [ ] **Step 3: Implement.** `recover_address/2` uses `Base.decode16/2` and matches the 65-byte shape in a `with`, returning `{:error, :invalid_signature}` otherwise; non-binary input hits a fallback clause. Make sure both LiveViews' `{:error, _}` branch shows "Signature verification failed. Please try again."
- [ ] **Step 4: Run** — expect pass.
- [ ] **Step 5: Commit** `Reject malformed wallet signatures without crashing`.

### Task 4: Magic link logs in (bug 5)

**Bug:** The welcome page tells magic-link users to save `/users/<token>`, which shows a bare record page and leaves them logged out. Only `/u/<token>` logs in.

**Files:**
- Modify: `lib/nullzara_web/controllers/token_html/magiclink_welcome.html.heex`, `lib/nullzara_web/plugs/auth.ex` (`on_mount(:require_admin_or_magiclink, ...)`), `lib/nullzara_web/live/user_live/show.ex` (`lookup_user/1`), `README.md` / `guides/admin.md` where they describe `/users/<token>`
- Test: `test/nullzara_web/live/user_live_test.exs`, `test/nullzara_web/controllers/page_controller_test.exs` or `token_controller_test.exs` (whichever covers the magic-link welcome page)

- [ ] **Step 1: Write failing tests.** Replace the existing "the holder of a magic link can still open their own record" test:

```elixir
test "a magic link at /users/<token> redirects to the login link", %{conn: conn} do
  {:ok, user} = Nullzara.Users.create_magiclink_user(%{name: "magic user"})
  token = user.raw_login_token
  assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/users/#{token}")
  assert to == ~p"/u/#{token}"
end

test "an admin opening /users/<magic token> sees the record and stays themselves" do
  # signed-in admin; live(conn, ~p"/users/#{token}") renders "Show User" and "magic user";
  # get(conn, ~p"/") afterwards still shows the admin as signed in
end
```

Add a welcome-page test asserting the rendered link is `#{NullzaraWeb.Endpoint.url()}/u/<token>` and that `/users/<token>` no longer appears.

- [ ] **Step 2: Run** — expect failures.
- [ ] **Step 3: Implement.** Welcome template prints `/u/{@token}`. In the hook, the magic-link branch becomes `{:halt, redirect(socket, to: "/u/#{token}")}` (admins are checked first, so they still see the record). Keep `lookup_user/1`'s token branch for the admin case. Update the hook's comment and the docs.
- [ ] **Step 4: Run** — expect pass.
- [ ] **Step 5: Commit** `Make the magic link log in instead of showing a record page`.

### Task 5: Token regeneration keeps a magic-link user's identity (bug 6)

**Bug:** For a magic-link account, regenerating the login token changes the slug (seeded from `token_hash`) and leaves the old, now invalid token in the session, so every navbar link uses a dead token.

**Files:**
- Modify: `lib/nullzara/users/user.ex` (`slug/1`), `lib/nullzara_web/controllers/settings_controller.ex` (`regenerate_token/2`)
- Test: `test/nullzara/users_test.exs`, `test/nullzara_web/controllers/settings_controller_test.exs`

- [ ] **Step 1: Write failing tests**

```elixir
# users_test.exs
test "a magic-link user's slug survives regenerating the login token" do
  {:ok, user} = Users.create_magiclink_user(%{name: "m"})
  {:ok, updated} = Users.regenerate_login_token(user)
  assert User.slug(updated) == User.slug(user)
end

# settings_controller_test.exs — conn signed in as a magic-link user via GET /u/<token>
test "regenerating twice keeps a magic-link user signed in with working links", %{conn: conn} do
  conn = post(conn, ~p"/user/#{old_token}/settings/token")
  new_token = get_session(conn, :login_token)
  assert new_token != old_token
  assert redirected_to(conn) == ~p"/user/#{new_token}/settings"
  conn = post(recycle(conn), ~p"/user/#{new_token}/settings/token")
  newest = get_session(conn, :login_token)
  assert html_response(get(recycle(conn), ~p"/user/#{newest}/settings"), 200)
end
```

- [ ] **Step 2: Run** — expect failures.
- [ ] **Step 3: Implement.** `User.slug/1` for `mnemonic_hash: nil` seeds from `uuid`. `regenerate_token/2`: for a magic-link user, `put_session(:login_token, updated_user.raw_login_token)` and redirect with `updated_user`. Non-magic-link behaviour is unchanged.
- [ ] **Step 4: Run** — expect pass.
- [ ] **Step 5: Commit** `Keep magic-link identity and session across token regeneration`.

### Task 6: Navbar shows the signed-in user on LiveView pages (bug 7)

**Bug:** `/users*` and `/access/*` LiveViews call `<Layouts.app flash={@flash}>` without `current_user`, so a signed-in user sees the logged-out navbar.

**Files:**
- Modify: `lib/nullzara_web/router.ex` (wrap the four `/access/*` live routes in `live_session :public, on_mount: [{NullzaraWeb.Plugs.Auth, :mount_current_user}]`), and add `current_user={@current_user}` in `access_token_live.ex`, `access_live.ex`, `passkey_live.ex`, `wallet_live.ex`, `user_live/index.ex`, `user_live/form.ex`, `user_live/show.ex`
- Test: `test/nullzara_web/live/user_live_test.exs`, `test/nullzara_web/live/access_token_live_test.exs`

- [ ] **Step 1: Write failing tests.** For `/users` (as admin) and `/access/token` (signed in): `assert has_element?(view, ~s|form[action="/logout"]|)` and `refute has_element?(view, ~s|a[href="/access/passkey"]|)`. Add the mirror-image assertion for a logged-out visitor on `/access/token`.
- [ ] **Step 2: Run** — expect the signed-in cases to fail.
- [ ] **Step 3: Implement** as listed under Files.
- [ ] **Step 4: Run** — expect pass.
- [ ] **Step 5: Commit** `Show the signed-in navbar on LiveView pages`.

### Task 7: Responsive navbar and flash placement (bugs 8, 9)

**Bugs:** At 375px wide the page is 1215px wide. Flash messages sit on top of the Settings and Logout buttons.

**Files:**
- Modify: `lib/nullzara_web/components/layouts.ex` (`app/1`), `lib/nullzara_web/components/core_components.ex` (`flash/1`)

No ExUnit test can measure layout; this task is verified in a browser.

- [ ] **Step 1: Implement the navbar.** Header and the action list get `flex-wrap` with a gap; the action list's `flex-column` typo is removed; the identity text gets `min-w-0` and truncates; the wallet address is hidden below `sm`; button labels are hidden below `sm` (icon only, with `aria-label` carrying the label).
- [ ] **Step 2: Move flashes** from `toast-top` to `toast-bottom` in `flash/1`.
- [ ] **Step 3: Verify in a browser** (Playwright plugin, server on a free port, dev admin login). At 375, 768 and 1280px, on `/`, `/access/token`, the dashboard, settings and `/users`, logged out and logged in: `document.documentElement.scrollWidth <= window.innerWidth`. Trigger a flash on settings and confirm Settings and Logout are clickable while it is shown. Check light and dark themes.
- [ ] **Step 4: Run** `mix precommit` — expect pass (existing tests that look for navbar text may need the label kept in the DOM; keep labels in a `sr-only`/`hidden sm:inline` span rather than removing them).
- [ ] **Step 5: Commit** `Make the navbar responsive and move flashes off the navbar`.

### Task 8: Login-form messages and navigation (minor issues)

**Issues:** (a) Passkey errors show raw structs like `%Wax.InvalidClientDataError{…}`. (b) A well-formed but wrong recovery phrase lands on the *token* page with "Invalid access token." (c) A stale error flash stays while a new phrase is typed. (d) Token and phrase login use `push_navigate` to a controller route, causing a full reload and a console warning.

**Files:**
- Modify: `lib/nullzara_web/live/passkey_live.ex` (lines ~196, ~249), `lib/nullzara_web/live/access_live.ex`, `lib/nullzara_web/live/access_token_live.ex`, `lib/nullzara_web/controllers/token_controller.ex`
- Test: `test/nullzara_web/live/passkey_live_test.exs`, `access_live_test.exs`, `access_token_live_test.exs`, `token_controller_test.exs`

- [ ] **Step 1: Write failing tests**
  - Passkey: drive a failing registration and a failing authentication the way the existing tests do; `refute render(view) =~ "%Wax"`; assert the text "Passkey registration failed. Please try again." / "Passkey sign-in failed. Please try again."
  - Token controller: `get(conn, ~p"/u/#{unknown}?via=mnemonic")` redirects to `/access/mnemonic` with flash "No account matches that recovery phrase."; without `via` it still goes to `/access/token` with "Invalid access token."
  - Access LiveViews: submitting now yields `{:error, {:redirect, %{to: ...}}}` (not `:live_redirect`); the phrase form redirects to `/u/<token>?via=mnemonic`; after an error flash, a `validate` event clears it.
- [ ] **Step 2: Run** — expect failures.
- [ ] **Step 3: Implement.** Passkey: fixed messages, and `Logger.warning` the inspected reason. Controller: branch on `params["via"] == "mnemonic"` in the not-found case (the failed attempt is still recorded with the rate limiter). LiveViews: `redirect/2` instead of `push_navigate/2`; `clear_flash(socket, :error)` in `validate`.
- [ ] **Step 4: Run** — expect pass.
- [ ] **Step 5: Commit** `Tidy login error messages and navigation`.

### Task 9: `:id` in `/user/:id/...` must match the signed-in account; theme toggle names (minor issues)

**Issues:** (a) Any value works as `:id` in `/user/:id/...`; the session user's page is shown regardless. (b) The three theme toggle buttons have no accessible names.

**Files:**
- Modify: `lib/nullzara_web/plugs/require_auth.ex`, `lib/nullzara_web/components/layouts.ex` (`theme_toggle/1`)
- Test: `test/nullzara_web/controllers/dashboard_controller_test.exs`, `settings_controller_test.exs`, `page_controller_test.exs`

**Interfaces:**
- Consumes: Task 5's behaviour that a magic-link user's session `:login_token` is always current.

- [ ] **Step 1: Write failing tests**
  - Signed in, `get(conn, ~p"/user/not-me/dashboard")` redirects to `~p"/user/#{user}/dashboard"`; same for another real user's UUID, and for `/user/not-me/settings`.
  - `put`/`post`/`delete` to a mismatched `:id` redirect and change nothing (assert the nickname and the account still exist).
  - A magic-link user is accepted under their current token and under their UUID.
  - Home page: `html =~ ~s|aria-label="Use system theme"|`, `"Use light theme"`, `"Use dark theme"`.
- [ ] **Step 2: Run** — expect failures.
- [ ] **Step 3: Implement.** `RequireAuth`, after confirming a signed-in user: if `conn.path_params["id"]` is present and is neither `Phoenix.Param.to_param(user)` nor `user.uuid`, redirect to the user's own dashboard and halt. Add the three `aria-label`s.
- [ ] **Step 4: Run** `mix precommit` — expect pass.
- [ ] **Step 5: Commit** `Check the account in /user/:id addresses and name the theme buttons`.

### Task 10: Final verification

- [ ] **Step 1:** `mix precommit` — expect all tests passing, no warnings.
- [ ] **Step 2:** Browser re-test of each original bug's reproduction (300-character nickname; upper-case token; capitalised phrase; saved magic link in a fresh browser; regenerate a magic-link token then click Settings; navbar on `/users` and `/access/token` while signed in; 375px width; flash over the navbar; malformed signature through a mock `window.ethereum`). Each must now behave as its task describes.
- [ ] **Step 3:** Update the bug list in the Claude memory directory to mark what is fixed.

## Not in this plan

- The two things the test pass did not cover (create-account rate limit, 60-second completion-token expiry) are still untested.
- The record page's "Edit user" and back buttons are now admin-only by construction (Task 4), so no change is needed there.
