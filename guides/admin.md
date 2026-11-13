# Admin users

Admins are the only accounts that can use the user administration pages under `/users`. This guide covers how to set up an admin and what an admin can do, in development and in production.

## How it works

- An account is an admin when its UUID is in the app's admin list.
- In production the list comes from the `ADMIN_UUIDS` environment variable. With it unset, there are no admins.
- In development the list defaults to one seeded account, the "Dev Admin".
- The list is read once when the app boots, so a change needs a restart.
- Being an admin does not replace signing in. An admin signs in like any other account (token, recovery phrase, passkey or wallet).

## Development

### 1. Create the dev admin

On a new checkout, `mix setup` creates it:

```bash
mix setup
```

On a database that already exists, run the seed script. It is safe to run more than once:

```bash
mix run priv/repo/seeds.exs
```

`mix ecto.reset` drops the database and recreates the dev admin with it.

### 2. Start the server

```bash
mix phx.server
```

### 3. Sign in as the dev admin

Open <http://localhost:4000/u/000000000000000000000000000000ad>. You land on the Dev Admin's dashboard.

You can also paste the token `000000000000000000000000000000ad` into the form at `/access/token`.

### 4. Open the admin pages

Go to <http://localhost:4000/users>. See [Using the admin pages](#using-the-admin-pages).

### Making a different account the admin in development

Set `ADMIN_UUIDS` when you start the server. It replaces the default list, so the Dev Admin stops being an admin unless you include its UUID (`00000000-0000-4000-8000-000000000001`):

```bash
ADMIN_UUIDS="<account uuid>" mix phx.server
```

### Where the dev admin is defined

The UUID, name and tokens are in `config/dev.exs` under `config :nullzara, :dev_admin`. The seed script `priv/repo/seeds.exs` creates the account from that config.

These credentials are public, because they are in the repository. They exist only in the development config, and the seed script does nothing in other environments. Never copy them into production.

## Production

There is no default admin in production. You choose an existing account and list its UUID.

### 1. Create the account

Open the site and create an account the normal way. Save its recovery phrase or login link, as for any account.

### 2. Find the account's UUID

For an account created with a recovery phrase, the UUID is in the dashboard address after signing in:

```
https://<your host>/user/486cd7fe-5521-421f-a591-219103c0830c/dashboard
                         └──────────── UUID ─────────────────┘
```

For a magic-link account the address contains the login token, not the UUID. Look the UUID up in the database instead, for example by nickname:

```sql
SELECT uuid, name, inserted_at FROM users WHERE name = '<nickname>';
```

### 3. Set `ADMIN_UUIDS`

Set the variable in the environment the app runs in. Separate several admins with commas:

```bash
ADMIN_UUIDS="486cd7fe-5521-421f-a591-219103c0830c,5f3ae4f5-d40b-422e-916c-3969c86fadce"
```

Spaces around entries and upper or lower case don't matter.

### 4. Restart the app

```bash
PHX_SERVER=true bin/nullzara start
```

If an entry is not a valid UUID, the app refuses to start and reports `ADMIN_UUIDS contains an invalid UUID`. Fix the value and start again.

### 5. Check it

Sign in as the admin account and open `/users`. The user list should load.

Then sign in as an account that is not listed and open `/users`. You should be sent to that account's dashboard with "You are not authorized to view that page."

### Adding or removing an admin

Edit `ADMIN_UUIDS` and restart the app. Removing a UUID takes that account's admin access away at the next boot. Unsetting the variable removes all admins.

## Using the admin pages

| Page | What an admin can do |
| --- | --- |
| `/users` | See every account, and delete one |
| `/users/new` | Create an account |
| `/users/<uuid>` | View one account's record |
| `/users/<uuid>/edit` | Change an account's nickname |

Deleting an account is permanent, and an admin can delete any account, including their own.

## Who gets what

| Visitor | `/users`, `/users/new`, `/users/<uuid>/edit` | `/users/<id>` |
| --- | --- | --- |
| Admin | Allowed | Allowed |
| Signed in, not an admin | Sent to own dashboard with an error | Sent to own dashboard with an error |
| Not signed in | Sent to `/access/token` | Sent to `/access/token` |
| Holder of a magic-link token | Same as above | Allowed for their own record at `/users/<token>` |

## Troubleshooting

- **"You are not authorized to view that page."** The signed-in account's UUID is not in the admin list. Check the value of `ADMIN_UUIDS` and that the app was restarted after changing it.
- **The dev admin link shows "Invalid access token."** The account has not been seeded in this database. Run `mix run priv/repo/seeds.exs`.
- **The dev admin signs in but `/users` is refused.** `ADMIN_UUIDS` is set in your shell and replaces the default list. Unset it or add the Dev Admin's UUID.
- **The app won't boot after setting `ADMIN_UUIDS`.** One entry is not a UUID. The error message names it.
