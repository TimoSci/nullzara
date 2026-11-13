# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Nullzara.Repo.insert!(%Nullzara.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

# Development only: create the default admin account described by
# `config :nullzara, :dev_admin` in config/dev.exs. Other environments do
# not set that config, so this does nothing there. Safe to run repeatedly.
if dev_admin = Application.get_env(:nullzara, :dev_admin) do
  alias Nullzara.Repo
  alias Nullzara.Users.User

  hash = fn token -> :crypto.hash(:sha256, token) |> Base.encode16(case: :lower) end

  if Repo.get_by(User, uuid: dev_admin[:uuid]) do
    IO.puts("Dev admin already exists.")
  else
    Repo.insert!(%User{
      uuid: dev_admin[:uuid],
      name: dev_admin[:name],
      token_hash: hash.(dev_admin[:login_token]),
      mnemonic_hash: hash.(dev_admin[:mnemonic_token])
    })

    IO.puts("Created dev admin.")
  end

  IO.puts("Sign in as the dev admin at /u/#{dev_admin[:login_token]}")
end
